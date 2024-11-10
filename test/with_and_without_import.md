# This is my readme

And here is some Gleam code that's ok:
```gleam
import filepath

pub fn main() {
  let path = filepath.join("/home/lucy", "pokemon-cards")
}
``` 

And here is some Gleam code that does not start with import:
```gleam
pub fn main() {
  list.filter([], 42)
}
```