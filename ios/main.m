// iOS entry: hand the process to the Rust client (winit runs UIApplicationMain itself).
extern void nostalre_ios_main(void);

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;
    nostalre_ios_main();
    return 0;
}
