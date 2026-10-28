#import <Foundation/Foundation.h>
#import "../launcher/WoW/CASC.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 4) {
            fprintf(stderr, "Usage: inject_casc_artifact <casc_data_dir> <artifact_raw_path> <ekey_hex>\n");
            return 2;
        }
        NSString *cascDir = @(argv[1]);
        NSString *rawPath = @(argv[2]);
        NSString *eKey = @(argv[3]);

        NSError *error = nil;
        NSData *raw = [NSData dataWithContentsOfFile:rawPath options:0 error:&error];
        if (!raw) {
            fprintf(stderr, "Failed to read artifact: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }

        printf("Loading CASC store from: %s\n", cascDir.UTF8String);
        TKWoWCASCStore *store = [[TKWoWCASCStore alloc] initWithDirectory:cascDir error:&error];
        if (!store) {
            fprintf(stderr, "Failed to open CASC store: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }

        printf("Adding artifact %s (%lu bytes)...\n", eKey.UTF8String, (unsigned long)raw.length);
        if (![store addData:raw key:eKey error:&error]) {
            fprintf(stderr, "Failed to add data: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }

        printf("Checkpointing CASC store...\n");
        if (![store checkpoint:&error]) {
            fprintf(stderr, "Failed to checkpoint: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }

        printf("Verifying artifact read back...\n");
        NSData *readBack = [store readKey:eKey size:0];
        if (!readBack) {
            fprintf(stderr, "Failed to read back artifact after checkpoint!\n");
            return 1;
        }
        printf("Verification SUCCEEDED! Read back %lu bytes decoded.\n", (unsigned long)readBack.length);
    }
    return 0;
}
