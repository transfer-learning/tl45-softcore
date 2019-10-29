    ADDI r1, r0, 0  ; int x1 = 0 (smaller)
    ADDI r2, r0, 1  ; int x2 = 1 (larger)

    ADDI r3, r0, 10 ; int iterations = 10

    ADDI r5, r0, 0x100

loop:
    JEi done

    ADD r1, r1, r2  ; x1 = x1 + x2

    ADD r3, r2, r0
    ADD r2, r1, r0
    ADD r1, r3, r0
    ; XCHG r1, r2     ; x1, x2 = x2, x1

    ; OUT r2, 0xFF
    SW r2, r5, 0
    ADDI r3, r3, -1  ; Load flags for r3

    JMPi  loop

    done:
    ADD r4, r0, r2  ; r4 = r2
    HALT

; 0 1 1 2 3 5 8
