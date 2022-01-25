use clap::Parser;
use std::io;
use std::process::exit;

#[derive(Parser)]
#[clap(
    about = "bcrypt commandline tool",
    long_about = "A tiny command line tool to hash a given string using the bcrypt algorithm.\
        Default cost used is 10, but can be configured. \
        The output is only the hash, so that this can be used for automation purposes without any parsing.",
    author
)]
struct Opts {
    #[clap(short, long, default_value = "10")]
    cost: u8,
}

fn main() {
    let opts = Opts::parse();

    // Read from stdin and fail on error
    let mut input = String::new();
    io::stdin().read_line(&mut input).unwrap_or_else(|error| {
        eprintln!("error: {}", error);
        exit(-1);
    });

    // Hash what we read
    match bcrypt::hash(&input, opts.cost.into()) {
        Ok(hashed) => {
            println!("{}", hashed);
            exit(0);
        }
        Err(error) => {
            eprintln!("error: {:?}", error);
            exit(-1);
        }
    }
}
