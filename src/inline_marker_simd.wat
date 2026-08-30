(module
  (memory (export "memory") 1)

  (func $is_marker (param $byte i32) (result i32)
    local.get $byte
    i32.const 10
    i32.eq
    local.get $byte
    i32.const 33
    i32.eq
    i32.or
    local.get $byte
    i32.const 38
    i32.eq
    i32.or
    local.get $byte
    i32.const 42
    i32.eq
    i32.or
    local.get $byte
    i32.const 58
    i32.eq
    i32.or
    local.get $byte
    i32.const 60
    i32.eq
    i32.or
    local.get $byte
    i32.const 91
    i32.eq
    i32.or
    local.get $byte
    i32.const 92
    i32.eq
    i32.or
    local.get $byte
    i32.const 93
    i32.eq
    i32.or
    local.get $byte
    i32.const 95
    i32.eq
    i32.or
    local.get $byte
    i32.const 96
    i32.eq
    i32.or
    local.get $byte
    i32.const 126
    i32.eq
    i32.or)

  ;; Return the first inline-marker byte, -1 for an ASCII miss, or -2 when
  ;; non-ASCII appears before a marker. In the latter case the caller falls
  ;; back to the UTF-16 scalar scanner so code-unit offsets stay exact.
  (func (export "find_inline_marker")
    (param $ptr i32) (param $len i32) (result i32)
    (local $i i32)
    (local $end16 i32)
    (local $v v128)
    (local $low v128)
    (local $high v128)
    (local $low_class v128)
    (local $high_bit v128)
    (local $interesting i32)
    (local $found i32)
    (local $byte i32)

    local.get $len
    i32.const -16
    i32.and
    local.set $end16

    block $vector_done
      loop $vector
        local.get $i
        local.get $end16
        i32.ge_u
        br_if $vector_done

        local.get $ptr
        local.get $i
        i32.add
        v128.load
        local.tee $v
        v128.const i8x16 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15
        v128.and
        local.set $low

        local.get $v
        i32.const 4
        i8x16.shr_u
        local.set $high

        v128.const i8x16 64 4 0 0 0 0 4 0 0 0 13 32 40 32 -128 32
        local.get $low
        i8x16.swizzle
        local.set $low_class

        v128.const i8x16 1 2 4 8 16 32 64 -128 0 0 0 0 0 0 0 0
        local.get $high
        i8x16.swizzle
        local.set $high_bit

        local.get $low_class
        local.get $high_bit
        v128.and
        v128.const i8x16 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
        i8x16.ne
        i8x16.bitmask
        local.get $v
        i8x16.bitmask
        i32.or
        local.tee $interesting
        if
          local.get $i
          local.get $interesting
          i32.ctz
          i32.add
          local.tee $found
          local.get $ptr
          i32.add
          i32.load8_u
          i32.const 128
          i32.ge_u
          if
            i32.const -2
            return
          end
          local.get $found
          return
        end

        local.get $i
        i32.const 16
        i32.add
        local.set $i
        br $vector
      end
    end

    block $not_found
      loop $tail
        local.get $i
        local.get $len
        i32.ge_u
        br_if $not_found
        local.get $ptr
        local.get $i
        i32.add
        i32.load8_u
        local.tee $byte
        i32.const 128
        i32.ge_u
        if
          i32.const -2
          return
        end
        local.get $byte
        call $is_marker
        if
          local.get $i
          return
        end
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $tail
      end
    end
    i32.const -1)
)
