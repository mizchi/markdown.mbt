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
async fn write_error(message : String, exit_code : Int) -> Unit {
  @stdio.stderr.write("mmmd: " + message + "\n") catch {
    _ => ()
  }
  @sys.exit(exit_code)
}

///|
async fn main {
  match parse_format(@env.args()) {
    Err(message) => write_error(message + "\n" + usage(), 2)
    Ok(format) => {
      let source = @stdio.stdin.read_all().text() catch {
        error => {
          write_error("unable to read standard input: \{error}", 1)
          return
        }
      }
      @stdio.stdout.write(@renderer.render(source, format)) catch {
        error => write_error("unable to write standard output: \{error}", 1)
      }
    }
  }
}
