///| Entity reference decoding tests.

///|
fn decoded(input : String) -> String {
  match decode_entity(input, 0) {
    Some((value, end)) => value + "|" + end.to_string()
    None => "none"
  }
}

///|
test "named character references" {
  inspect(decoded("&amp;"), content="&|5")
  inspect(decoded("&copy;"), content="©|6")
  inspect(decoded("&ClockwiseContourIntegral;"), content="∲|26")
  // Multi-code-point replacements are supported too.
  inspect(decoded("&ngE;"), content="≧̸|5")
}

///|
test "unknown and malformed references are left alone" {
  inspect(decoded("&MadeUpEntity;"), content="none")
  inspect(decoded("&amp"), content="none")
  inspect(decoded("&#;"), content="none")
  inspect(decoded("&"), content="none")
}

///|
test "numeric character references" {
  inspect(decoded("&#35;"), content="#|5")
  inspect(decoded("&#x22;"), content="\"|6")
  inspect(decoded("&#X22;"), content="\"|6")
}

///|
test "code points outside Unicode become the replacement character" {
  inspect(decoded("&#0;"), content="\u{fffd}|4")
  inspect(decoded("&#xD800;"), content="\u{fffd}|8")
  inspect(decoded("&#x110000;"), content="\u{fffd}|10")
}
