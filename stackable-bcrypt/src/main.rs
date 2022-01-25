use clap::Parser;
use std::process::exit;

#[derive(Parser)]
#[clap(
    about = "bcrypt commandline tool",
    long_about = "A tiny command line tool to hash a given string using the bcrypt algorithm.\
        Default cost used is 10, but can be configured. \
        The output is only the hash, so that this can be used for automation purposes without any parsing.",
    author = "Stackable GmbH - info@stackable.de"
)]
struct Opts {
    #[clap(short, long, default_value = "10")]
    cost: u8,
    #[clap(short, long)]
    input: String,
}

fn main() {
    let opts = Opts::parse();
    match bcrypt::hash(opts.input, opts.cost.into()) {
        Ok(hashed) => {
            println!("{}", hashed);
        }
        Err(error) => {
            eprintln!("Failed to hash: {:?}", error);
            exit(-1);
        }
    }
}
