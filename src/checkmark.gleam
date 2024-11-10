import gleam/io

pub type Operation {
  Check
  Build
  Run
}

pub type CheckError {
  CouldNotRun(String)
  CheckFailed(String)
}

pub fn main() {
  io.println("Hello from checkmark!")
}
