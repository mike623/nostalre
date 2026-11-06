// ponytail: debug helper — dump one file from a GRF to stdout
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let grf = nostalre_formats::grf::GrfArchive::open(std::path::Path::new(&a[1])).expect("open");
    let d = grf.read_file(&a[2]).expect("read");
    use std::io::Write;
    std::io::stdout().write_all(&d).unwrap();
}
