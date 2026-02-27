use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
struct Message {
    text: String,
    author: String,
}

fn main() {
    let msg = Message {
        text: String::from("Nix Seed"),
        author: String::from("King Art"),
    };


    let j = serde_json::to_string(&msg).unwrap();
    println!("Serialized: {}", j);
}
