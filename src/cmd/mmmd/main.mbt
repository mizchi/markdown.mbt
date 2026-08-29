///|
fn usage() -> String {
  "Usage: mmmd --format tui|html < input.md"
}

///|
fn parse_format(args : Array[String]) -> Result[@renderer.OutputFormat, String] {
  if args.length() != 3 {
    return Err("--format tui or --format html is required")
  }
  if args[1] != "--format" {
    return Err("unsupported option: " + args[1])
  }
  match @renderer.OutputFormat::parse(args[2]) {
    Some(format) => Ok(format)
    None => Err("--format must be tui or html")
  }
}

///|
fn write_error(message : String, exit_code : Int) -> Unit {
  @fs.write_string_to_file("/dev/stderr", "mmmd: " + message + "\n") catch {
    _ => ()
  }
  @sys.exit(exit_code)
}

///|
fn main {
  match parse_format(@env.args()) {
    Err(message) => write_error(message + "\n" + usage(), 2)
    Ok(format) => {
      let source = @fs.read_file_to_string("/dev/stdin") catch {
        @fs.IOError(message) => {
          write_error("unable to read standard input: " + message, 1)
          return
        }
      }
      @fs.write_string_to_file("/dev/stdout", @renderer.render(source, format)) catch {
        @fs.IOError(message) =>
          write_error("unable to write standard output: " + message, 1)
      }
    }
  }
}
