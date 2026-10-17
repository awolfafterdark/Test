/* Small, fail-closed Mach-O load-command injector. Supports thin little-endian arm64.
 * No payload bytes or offsets are shifted; insufficient header padding is an error.
 * Input signatures become invalid and the resulting IPA must be re-signed by TrollStore.
 */
#define _DARWIN_C_SOURCE 1
#define _POSIX_C_SOURCE 200809L
#include "MachOInject.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#define MH_MAGIC_64 0xfeedfacfu
#define CPU_TYPE_ARM64 0x0100000cu
#define LC_SEGMENT_64 0x19u
#define LC_LOAD_DYLIB 0xcu
#define LC_ENCRYPTION_INFO_64 0x2cu
#define LC_REQ_DYLD 0x80000000u

static uint32_t u32(const unsigned char *p) {
    return (uint32_t)p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24;
}
static void put32(unsigned char *p, uint32_t v) {
    for (int i=0; i<4; i++) p[i] = (unsigned char)(v >> (8*i));
}
static int fail(char *err, size_t cap, const char *why) {
    if (cap) snprintf(err, cap, "%s", why);
    return -1;
}
int PPInjectDylib(const char *binary, const char *loadPath, char *err, size_t cap) {
    int fd = -1, result = -1;
    unsigned char *buf = NULL;
    struct stat st;
    if (!binary || !loadPath || !*loadPath || strlen(loadPath) > 1024)
        return fail(err, cap, "Invalid input or load path");
    fd = open(binary, O_RDWR | O_NOFOLLOW);
    if (fd < 0 || fstat(fd, &st) || !S_ISREG(st.st_mode)) {
        fail(err, cap, "Cannot open a regular executable"); goto done;
    }
    if (st.st_size < 32) { fail(err, cap, "Executable too short"); goto done; }
    unsigned char hdr[32];
    if (pread(fd, hdr, sizeof hdr, 0) != sizeof hdr || u32(hdr) != MH_MAGIC_64 ||
        u32(hdr+4) != CPU_TYPE_ARM64) {
        fail(err, cap, "Only thin little-endian arm64 Mach-O is supported"); goto done;
    }
    uint32_t count=u32(hdr+16), size=u32(hdr+20);
    if (count > 4096 || size > 16*1024*1024 || (uint64_t)size+32 > (uint64_t)st.st_size) {
        fail(err, cap, "Malformed Mach-O load commands"); goto done;
    }
    size_t cmdEnd = 32u + size;
    size_t cmdSize = (24u + strlen(loadPath) + 1u + 7u) & ~(size_t)7u;
    if (cmdEnd + cmdSize > 16*1024*1024) {
        fail(err, cap, "Mach-O header exceeds safety limit"); goto done;
    }
    buf = calloc(1, cmdEnd + cmdSize);
    if (!buf || pread(fd, buf, cmdEnd, 0) != (ssize_t)cmdEnd) {
        fail(err, cap, "Cannot read Mach-O load commands"); goto done;
    }
    size_t offset=32;
    uint64_t firstSection=UINT64_MAX;
    for (uint32_t i=0; i<count; i++) {
        if (offset+8 > cmdEnd) { fail(err,cap,"Truncated load command"); goto done; }
        uint32_t type=u32(buf+offset), length=u32(buf+offset+4);
        if (length < 8 || length%8 || length > cmdEnd-offset) {
            fail(err,cap,"Invalid load command size"); goto done;
        }
        if ((type & ~LC_REQ_DYLD) == LC_LOAD_DYLIB && length >= 24) {
            uint32_t start=u32(buf+offset+8);
            if (start >= 24 && start < length &&
                memchr(buf+offset+start, '\0', length-start) &&
                strcmp((const char *)buf+offset+start, loadPath)==0) {
                fail(err,cap,"PickerPatcher is already injected"); goto done;
            }
        }
        if (type == LC_ENCRYPTION_INFO_64) {
            if (length < 24 || u32(buf+offset+16)) {
                fail(err,cap,"Encrypted or malformed Mach-O executable"); goto done;
            }
        }
        if (type == LC_SEGMENT_64) {
            if (length < 72) { fail(err,cap,"Malformed segment"); goto done; }
            uint32_t sections=u32(buf+offset+64);
            if (sections > (length-72)/80) { fail(err,cap,"Malformed section table"); goto done; }
            for (uint32_t j=0;j<sections;j++) {
                uint32_t sectionOffset=u32(buf+offset+72+j*80+48);
                uint64_t sectionSize=(uint64_t)u32(buf+offset+72+j*80+40) |
                                     (uint64_t)u32(buf+offset+72+j*80+44)<<32;
                if (sectionOffset && sectionSize && sectionOffset < firstSection)
                    firstSection=sectionOffset;
            }
        }
        offset += length;
    }
    if (offset != cmdEnd || firstSection == UINT64_MAX || firstSection > (uint64_t)st.st_size ||
        cmdEnd + cmdSize > firstSection) {
        fail(err,cap,"No verified header padding for a new load command"); goto done;
    }
    unsigned char *padding=malloc(cmdSize);
    if (!padding || pread(fd,padding,cmdSize,(off_t)cmdEnd)!=(ssize_t)cmdSize) {
        free(padding); fail(err,cap,"Cannot inspect header padding"); goto done;
    }
    int nonzero=0;
    for (size_t i=0;i<cmdSize;i++) nonzero |= padding[i];
    free(padding);
    if (nonzero) { fail(err,cap,"Header padding contains data"); goto done; }
    unsigned char *newcmd=buf+cmdEnd;
    put32(newcmd,LC_LOAD_DYLIB);
    put32(newcmd+4,(uint32_t)cmdSize);
    put32(newcmd+8,24);
    put32(newcmd+12,2); /* dylib timestamp */
    put32(newcmd+16,0x10000); /* current version */
    put32(newcmd+20,0x10000); /* compatibility version */
    memcpy(newcmd+24,loadPath,strlen(loadPath)+1);
    if (pwrite(fd,newcmd,cmdSize,(off_t)cmdEnd)!=(ssize_t)cmdSize) {
        fail(err,cap,"Cannot write load command"); goto done;
    }
    put32(hdr+16,count+1);
    put32(hdr+20,size+(uint32_t)cmdSize);
    if (pwrite(fd,hdr,sizeof hdr,0)!=sizeof hdr || fsync(fd)) {
        fail(err,cap,"Cannot finalize Mach-O header"); goto done;
    }
    result=0;
done:
    free(buf);
    if (fd >= 0) close(fd);
    return result;
}
#ifdef PP_STANDALONE
int main(int argc, char **argv) {
    char error[256]={0};
    if (argc!=3) { fprintf(stderr,"Usage: %s EXECUTABLE LOAD_PATH\n",argv[0]); return 2; }
    if (PPInjectDylib(argv[1],argv[2],error,sizeof error)) {
        fprintf(stderr,"PickerPatcher: %s\n",error); return 1;
    }
    return 0;
}
#endif
