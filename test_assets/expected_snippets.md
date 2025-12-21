```gleam function
pub fn main() {
  todo
}
```

```gleam function body
todo
```

```gleam type
pub type Wibble {
  Wibble
  Wobble
}
```

Empty blocks should be also replaced properly:
```gleam type alias
type Wobble = Wibble
```
