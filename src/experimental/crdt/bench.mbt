///| CRDT experiment benchmarks

// LogicalId generation overhead

///|
test "crdt: LogicalId generation 1000x" (b : @bench.T) {
  let gen = IdGenerator::new(AgentId(1))
  b.bench(fn() {
    for i = 0; i < 1000; i = i + 1 {
      let _ = gen.next()
    }
    b.keep(gen)
  })
}

// LogicalId comparison overhead

///|
test "crdt: LogicalId compare 1000x" (b : @bench.T) {
  let gen = IdGenerator::new(AgentId(1))
  let ids : Array[LogicalId] = []
  for i = 0; i < 100; i = i + 1 {
    ids.push(gen.next())
  }
  b.bench(fn() {
    let mut count = 0
    for i = 0; i < 100; i = i + 1 {
      for j = 0; j < 10; j = j + 1 {
        if ids[i].lt(ids[(i + j) % 100]) {
          count += 1
        }
      }
    }
    b.keep(count)
  })
}

// CrdtDocument insertion overhead

///|
test "crdt: CrdtDocument insert 100 runs" (b : @bench.T) {
  b.bench(fn() {
    let doc = CrdtDocument::new(AgentId(1))
    for i = 0; i < 100; i = i + 1 {
      let _ = doc.insert("Hello World ")
    }
    b.keep(doc)
  })
}

// Impact of tombstone accumulation

///|
test "crdt: CrdtDocument with 50% tombstones" (b : @bench.T) {
  let doc = CrdtDocument::new(AgentId(1))
  // Create 200 runs, delete half
  for i = 0; i < 200; i = i + 1 {
    let _ = doc.insert("Text ")
  }
  for i = 0; i < 100; i = i + 1 {
    doc.delete(i * 2) // Delete even indices
  }
  b.bench(fn() {
    let text = doc.get_text()
    b.keep(text)
  })
}

// For Span vs CrdtSpan size comparison

///|
test "crdt: CrdtSpan creation 1000x" (b : @bench.T) {
  let gen = IdGenerator::new(AgentId(1))
  b.bench(fn() {
    let mut last = CrdtSpan::new(gen.next(), gen.next(), 0, 0)
    for i = 0; i < 1000; i = i + 1 {
      last = CrdtSpan::new(gen.next(), gen.next(), i, i + 10)
    }
    b.keep(last)
  })
}
