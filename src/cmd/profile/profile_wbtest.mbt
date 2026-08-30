///|
test "parse profile configuration" {
  match parse_config(["markdown-profile", "parse", "25"]) {
    Ok(config) => {
      guard config.mode is ProfileMode::Parse else {
        fail("expected parse mode")
      }
      assert_true(config.iterations == 25)
    }
    Err(_) => fail("parse config must succeed")
  }
  match parse_config(["markdown-profile", "render", "10"]) {
    Ok(config) => {
      guard config.mode is ProfileMode::Render else {
        fail("expected render mode")
      }
      assert_true(config.iterations == 10)
    }
    Err(_) => fail("render config must succeed")
  }
  match parse_config(["markdown-profile", "parse-render", "5"]) {
    Ok(config) => {
      guard config.mode is ProfileMode::ParseRender else {
        fail("expected parse-render mode")
      }
      assert_true(config.iterations == 5)
    }
    Err(_) => fail("parse-render config must succeed")
  }
  match parse_config(["node", "profile.js", "parse", "7"]) {
    Ok(config) => {
      guard config.mode is ProfileMode::Parse else {
        fail("expected JS parse mode")
      }
      assert_true(config.iterations == 7)
    }
    Err(_) => fail("Node.js argv shape must succeed")
  }
}

///|
test "reject invalid profile configuration" {
  match parse_config(["markdown-profile", "other", "10"]) {
    Err(message) => assert_true(message == "unsupported mode: other")
    Ok(_) => fail("unsupported mode must fail")
  }
  match parse_config(["markdown-profile", "parse", "0"]) {
    Err(message) =>
      assert_true(message == "iterations must be a positive integer")
    Ok(_) => fail("zero iterations must fail")
  }
}
