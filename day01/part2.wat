(module
  (import "env" "memory" (memory 1))
  (global $data_start (import "env" "data_start") i32)
  (global $data_bytes (import "env" "data_bytes") i32)
  (global $list_length (import "env" "list_length") i32)
  ;; (import "env" "print_i32" (func $print_i32 (param i32)))

  ;; Precomputed powers of 10 for use when converting string to number.
  ;; WASM uses little endian so the least significant bytes go first.

  (data (i32.const 0)  "\01\00\00\00") ;; 1
  (data (i32.const 4)  "\0a\00\00\00") ;; 10
  (data (i32.const 8)  "\64\00\00\00") ;; 100
  (data (i32.const 12) "\e8\03\00\00") ;; 1_000
  (data (i32.const 16) "\10\27\00\00") ;; 10_000

  ;; MEMORY LAYOUT
  ;;
  ;; BYTE                                             DESCRIPTION
  ;; 0                                                Precomputed powers of 10
  ;; 󰇙
  ;; $data_start                                      Raw ASCII data
  ;; 󰇙
  ;; $data_start + $data_bytes                        Left list's first number
  ;; $data_start + $data_bytes + 4                    Left list's second number
  ;; 󰇙
  ;; $data_start + $data_bytes + $list_length * 4     Right list's first number
  ;; $data_start + $data_bytes + $list_length * 4 + 4 Right list's second number
  ;; 󰇙
  ;; $data_start + $data_bytes + $list_length * 8     Temporary buffer: ASCII of
  ;;                                                  the number being parsed.

  ;; Returns:
  ;; * 0 if the input byte was a whitespace
  ;; * 1 if the input byte was a whitespace and a number was inserted
  ;; * 2 if the input byte was a number
  (func $process_char
    (param $char i32)
    (param $temp_start i32)
    (param $list_id i32)
    (param $left_list_start i32)
    (param $right_list_start i32)
    (param $num_digits i32)
    (param $i i32)
    (param $last_result i32)

    (result i32)

    (local $number i32)      ;; the parsed number
    (local $temp_offset i32) ;; offset into the temporary buffer
    (local $list_start i32)  ;; $left_list_start or $right_list_start depending
                             ;; on $list_id

    local.get $char ;; Test if the character is a whitespace (space or newline)
    i32.const 32    ;; space
    i32.eq          ;;
                    ;;
    local.get $char ;;
    i32.const 10    ;; newline (linefeed)
    i32.eq          ;;
                    ;;
    i32.or          ;;

    (if
      (then ;; whitespace
        (block $last_char_is_ws
          local.get $last_result  ;; Proceed only if the last char was a number
          i32.const 2
          i32.ne
          br_if $last_char_is_ws

          (local.set $number (i32.const 0))
          (local.set $temp_offset (i32.const 0))

          (loop $num_digits_is_not_zero
            local.get $num_digits  ;; Calculate the offset into the powers table
            i32.const 1
            i32.sub
            i32.const 4
            i32.mul

            i32.load ;; Load the power of 10

            local.get $temp_start  ;; Find the digit (still in ASCII)
            local.get $temp_offset
            i32.add
            i32.load8_u

            i32.const 48           ;; ascii for '0'
            i32.sub

            i32.mul                ;; Add the digit with power to $number
            local.get $number
            i32.add
            local.set $number

            local.get $temp_offset ;; Increment $temp_offset
            i32.const 1
            i32.add
            local.set $temp_offset

            local.get $num_digits  ;; Decrement $num_digits
            i32.const 1
            i32.sub
            local.tee $num_digits

            i32.const 0            ;; Continue loop if there's still digits
            i32.ne
            br_if $num_digits_is_not_zero
          )

          ;; Now we have the $number, insert it into the correct list and do
          ;; insertion sort.

          (if (i32.eqz (local.get $list_id))
            (then
              local.get $left_list_start
              local.set $list_start
            )
            (else
              local.get $right_list_start
              local.set $list_start
            )
          )

          local.get $list_start
          local.get $i
          i32.const 4
          i32.mul
          i32.add
          local.get $number
          i32.store

          (return (i32.const 1))
        )

        (return (i32.const 0))
      )
      (else
                         ;; Check if '0' <= $char <= '9'
        i32.const 48     ;; ascii for '0'
        local.get $char  ;;
        i32.le_u         ;;
                         ;;
        local.get $char  ;;
        i32.const 57     ;; ascii for '9'
        i32.le_u         ;;
                         ;;
        i32.or           ;;

        (if
          (then ;; number
            local.get $temp_start ;; Copy the byte over to temporary buffer
            local.get $num_digits ;;
            i32.add               ;;
                                  ;;
            local.get $char       ;;
                                  ;;
            i32.store8            ;;

            (return (i32.const 2))
          )
        )
      )
    )

    i32.const 0
  )

  (func (export "solution") (result i32)
    ;; For scanning.

    (local $offset i32)      ;; the byte offset of the scanner
    (local $char i32)        ;; stores the char that is being read and processed
    (local $last_result i32) ;; the last result of $process_char

    ;; For list management.

    (local $list_id i32)          ;; 0 = left list, 1 = right list
    (local $i i32)                ;; the index in the list
    (local $left_list_start i32)  ;; the byte at which the left list starts
    (local $right_list_start i32) ;; the byte at which the right list starts

    ;; For number parsing.

    (local $num_digits i32) ;; the number of digits that have been read so far
                            ;; for the number being parsed
    (local $temp_start i32) ;; the byte where the temporary memory starts where
                            ;; the ASCII of the number being parsed is written
    
    ;; Result

    (local $offset_a i32)
    (local $offset_b i32)
    (local $count i32)
    (local $similarity_score i32)

    ;; Initializing to 0 might not be necessary?

    ;; (local.set $offset (i32.const 0))
    ;; (local.set $list_id (i32.const 0)) ;; Begin with reading for the left list.
    ;; (local.set $num_digits (i32.const 0))
    ;; (local.set $i (i32.const 0))
    ;; (local.set $total_distance (i32.const 0))

    ;; Calculate $left_list_start = $data_start + $data_bytes

    global.get $data_start
    global.get $data_bytes
    i32.add
    local.tee $left_list_start

    ;; Calculate $right_list_start = $left_list_start + $list_length * 4

    global.get $list_length
    i32.const 4
    i32.mul
    i32.add
    local.tee $right_list_start

    ;; Calculate $temp_start = $right_list_start + $list_length * 4.

    global.get $list_length
    i32.const 4
    i32.mul
    i32.add
    local.set $temp_start

    ;; Begin data parsing. Rough steps:
    ;;
    ;; 1. Read 1 (one) char (1 byte) at a time.
    ;; 2. If it is a space and the last char was a number:
    ;;    2.1. Parse the data at $temp_start from ASCII to integer.
    ;;    2.2. Insert it into $list_id using insertion sort.
    ;;    2.3. If $list_id == 1, increment $i.
    ;;    2.4. Flip $list_id.
    ;;    2.5. Reset $num_digits.
    ;; 3. If it is a number:
    ;;    3.1. Copy the byte over to the left list ($left_list_start) or the
    ;;         right list ($right_list_start) at offset $num_digits.
    ;;    3.2. Increment $num_digits.
    ;; 4. Otherwise:
    ;;    4.1. Set flag.
    ;;    4.2. Break.

    (loop $parsing
      (i32.add (global.get $data_start) (local.get $offset))
      i32.load8_u
      local.tee $char
      local.get $temp_start
      local.get $list_id
      local.get $left_list_start
      local.get $right_list_start
      local.get $num_digits
      local.get $i
      local.get $last_result

      call $process_char

      local.tee $last_result
      i32.const 1

      (if (i32.eq)              ;; A number was added to a list
        (then
          local.get $list_id    ;; If added to right list, move to next list pos
          i32.const 1

          (if (i32.eq)
            (then
              local.get $i
              i32.const 1
              i32.add
              local.set $i
            )
          )

          local.get $list_id    ;; Flip $list_id (left list <-> right list)
          i32.const 1
          i32.xor
          local.set $list_id

          i32.const 0           ;; Reset digit count
          local.set $num_digits
        )
        (else
          local.get $last_result
          i32.const 2

          (if (i32.eq)          ;; Char is a number
            (then
              local.get $num_digits
              i32.const 1
              i32.add
              local.set $num_digits
            )
          )
        )
      )

      local.get $offset           ;; Check if finished reading the ASCII data
      i32.const 1                 ;;
      i32.add                     ;;
      local.tee $offset           ;;
                                  ;;
      global.get $data_bytes      ;;
      (br_if $parsing (i32.lt_u)) ;;
    )

    ;; Now we have both lists read at $left_list_start and $right_list_start.

    local.get $i
    i32.const 4
    i32.mul
    local.set $i

    (loop $iter_left_list
      i32.const 0
      local.set $offset_b
      
      i32.const 0
      local.set $count

      (loop $iter_right_list
        local.get $left_list_start
        local.get $offset_a
        i32.add
        i32.load

        local.get $right_list_start
        local.get $offset_b
        i32.add
        i32.load

        i32.eq
        local.get $count
        i32.add
        local.set $count

        local.get $offset_b
        i32.const 4
        i32.add
        local.tee $offset_b

        local.get $i
        i32.lt_u
        br_if $iter_right_list
      )

      local.get $left_list_start
      local.get $offset_a
      i32.add
      i32.load

      local.get $count
      i32.mul
      local.get $similarity_score
      i32.add
      local.set $similarity_score

      local.get $offset_a
      i32.const 4
      i32.add
      local.tee $offset_a

      local.get $i
      i32.lt_u
      br_if $iter_left_list
    )

    i32.const 0
    local.get $similarity_score
    return
  )
)
