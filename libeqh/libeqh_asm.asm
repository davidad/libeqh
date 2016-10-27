format ELF64
include "syscalls.inc"

; ABI params
; User   Kernel
;       (rax)
; rdi    rdi
; rsi    rsi
; rdx    rdx
; rcx    r10
; r8     r8
; r9     r9

; ABI regs
; kernel destroys rcx and r11
; callee-saved: rbx, rsp, rbp, r12, r13, r14, r15
; destroyable: rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11, xmms, sts

; r15: blake state in stage 0, then position in pairs memory
; r14: points to hash output in stage 0, alternate hash output
; r13: temporary blake state in stage 0, then pairs memory
; r12: Hash Output + Bucket block

extrn 'crypto_generichash_blake2b_init_salt_personal' as blake2b_init:qword
extrn 'crypto_generichash_blake2b_update' as blake2b_update:qword
extrn 'crypto_generichash_blake2b_final' as blake2b_final:qword
extrn 'crypto_generichash_blake2b_statebytes' as blake2b_size:qword
blake_state_size = 384  ; value returned by blake2b_size

macro save [reg] {
  forward push qword reg
  common macro unsave \{
  reverse pop qword reg
  common purge unsave
  \}
}

; TODO: alignment for ymm etc.
macro mmap_allocate bytes {
  mov rsi, bytes
  mov rax, SYSCALL_MMAP
  xor rdi, rdi
  mov rdx, PROT_WRITE or PROT_READ
  mov r10, MAP_SHARED or MAP_ANON
  mov r8,  -1
  xor r9, r9
  syscall
  test rax, rax
  js libeqh_oom
}

macro copy_blake_state rd,rs {
  rept 24 i:0 \{
    vmovdqu ymm0, [rs+i*16]
    vmovdqu [rd+i*16], ymm0
  \}
}

; pack x bitstrings of length b from *rs to *rd (*rd pre-zeroed)
; using 32-bit register rz for scratch
macro bitpack x,b,rd,rs,rz {
  assert b <= 25
  assert ((b*x) mod 8) = 0
  rept x i:0 \{
    mov rz, dword [rs+4*i]
    shl rz, ((32-b)-((b*i) mod 8))
    bswap rz
    or dword [rd+((b*i)/8)], rz
  \}
}

public Bitpack_8_21
Bitpack_8_21:
; rdi is char* for destination
; rsi is uint32_t* for source integers
  bitpack 8,21,rdi,rsi,eax
  ret

macro Equihash n,k {
; parameter-dependent constants
  IndicesPerBlake = 512/n
  HashBytesPerIndex = n/8
  HashBytesNeeded = IndicesPerBlake*n/8
  CollisionBits = n/(k+1)
  CollisionBytes = CollisionBits/8
  NumIndices = 1 shl k
  IndexBits = CollisionBits + 1
  NumIndices = 1 shl IndexBits
  IndexWordSize = 4

  PossibleCollisions = 1 shl CollisionBits
  BucketSize = IndexWordSize * 8

  HashOutputBlockSize = NumIndices*HashBytesPerIndex
  BucketBlockOffset = HashOutputBlockSize
  BucketBlockSize = PossibleCollisions * BucketSize

  PairsPerStage = NumIndices
  TotalPairs = PairsPerStage * k
  PairSize = IndexWordSize * 2
  PairBlockSize = TotalPairs * PairSize

; parameter-dependent constraints
  assert n > 0 & k >= 3
  assert n mod 8 = 0
  assert n mod (k+1) = 0
  assert IndexBits < 32
  assert n <= 256
  
; declare API
  public Eqh_#n#_#k#_GiveN
  public Eqh_#n#_#k#_GiveK

  public Eqh_#n#_#k#_Validate

  Eqh_#n#_#k#_GiveN:
    mov rax, n
    ret
  Eqh_#n#_#k#_GiveK:
    mov rax, k
    ret

  macro initialize_blake_state \{
    mmap_allocate blake_state_size ; allocate this many bytes through anonymous mmap
    mov r15, rax              ; store blake state ptr in r15
    mov rdi, rax              ; put pointer to allocation in rdi for next call
    
    mov rax, "ZcashPoW"
    mov r11d, n
    mov r8d, k
    mov qword [rsp-16], rax
    mov dword [rsp-8], r11d
    mov dword [rsp-4], r8d
    xor rsi, rsi
    xor rdx, rdx
    mov ecx, HashBytesNeeded
    xor r8, r8
    mov r9, rsp
    call blake2b_init
  \}

  macro hash_input input_ptr,input_len \{
    assert ~(input_ptr eq rdx)
    mov rdx, input_len
    mov rsi, input_ptr
    mov rdi, r15
    call blake2b_update
  \}

  local check_bucket
  local bucket_full
  check_bucket:
    mov rax, qword [r14]
    and rax, (1 shl CollisionBits) - 1   ; Mask to keep the 'CollisionBits' least significant bits
    shl rax, 3                           ; Get offset into BucketBlock
    add rax, BucketBlockOffset
    add rax, r12
    ; now rax points directly to the bucket we want
    vzeroall
    vmovdqu ymm1, yword [rax]
    vpcmpeqd ymm2, ymm1, ymm0
    vpmovmskb ecx, ymm2
    not ecx
    tzcnt ecx, ecx
    jc bucket_full
    shr ecx, 2
    mov dword [rax+rcx], ebx
  bucket_full:
    ret

  macro gen_hashes \{
    mmap_allocate HashOutputBlockSize + BucketBlockSize
    mov r14, rax
    mov r12, rax
    push r14
    mmap_allocate blake_state_size
    mov r13, rax

    xor ebx, ebx
  local loop
  loop:
    copy_blake_state r13,r15
    mov rdi, r13
    lea rsi, [rsp-4]
    mov dword [rsp-4], ebx
    mov rdx, 4
    call blake2b_update
    mov rdi, r13
    mov rsi, r14
    mov rdx, HashBytesNeeded
    call blake2b_final
    ; having computed a hash, check corresponding bucket
    repeat IndicesPerBlake
      call check_bucket
      add r14, HashBytesPerIndex
    end repeat
    inc ebx
    cmp ebx, NumIndices/IndicesPerBlake
    jb loop
    
    pop rax
  \}

  macro do_xors prev,cur \{
  local begin
  local loop
    inc [stage]

    ; in this stage, load n*(k+1-stage)/8*(k+1) bytes
    Factor = n/(8*(k+1))
    KPlusOne = k+1
    mov eax, KPlusOne
    sub eax, stage
    mov r9d, Factor
    mul r9d
    mov r9, rax
    mov r10, r9
    sub r10, Factor

    mov ecx, [stage]
    sub ecx, 2
    local skip_freemem
    js skip_freemem
    ; TODO: munmap goes here
  skip_freemem:
    ; TODO: adaptive length etc.
    mmap_allocate HashOutputBlockSize
    mov cur, rax
    xor rsi, rsi
  loop:
    mov eax, dword [r13+rsi*PairSize]
    mov r8d, dword [r13+rsi*PairSize+4]
    mul r9
    mov ebx, eax
    mov rax, r8
    mul r9
    mov r8, rax
    vmovdqu ymm3, [prev+rbx]
    vmovdqu ymm4, [prev+r8]
    vpxor ymm5, ymm4, ymm3
    mov rax, rsi
    mul r10
    lea rax, [rax-(32-r10)]
    ; todo: set up ymm6
    vpmaskmovq [cur+rax], ymm6, ymm5
    inc rsi
    cmp rsi, r15
    jb loop
  \}

  public Eqh_#n#_#k#_Stage
  Eqh_#n#_#k#_Stage:
  ; rdi is pointer to I||V
  ; rsi is length of I||V (usually 140)
    save r12, r13, r14, r15, rbx, rbp
    mov r12, rdi
    mov r13, rsi
    initialize_blake_state
    hash_input r12, r13
    gen_hashes
    make_pairs
    do_xors r12, r14
    unsave
    ret

  public Eqh_#n#_#k#_GenHashes
  Eqh_#n#_#k#_GenHashes:
  ; rdi is pointer to I||V
  ; rsi is length of I||V (usually 140)
    save r12, r13, r14, r15, rbx, rbp
    mov r12, rdi
    mov r13, rsi
    initialize_blake_state
    hash_input r12, r13
    gen_hashes
    unsave
    ret
  
  Eqh_#n#_#k#_Validate:
  ; rdi is pointer to I||V
  ; rsi is length of I||V (usually 140)
  ; rdx is pointer to solution (in minimal rep)
    ret
    
  macro make_pair i,j \{
    PermConfig = i + (j shl 32)
    mov r8, PermConfig
    movq xmm1, r8
    vpbroadcastq ymm3, xmm1
    vpermd ymm4, ymm3, ymm1
    vextracti128 xmm1, ymm4, 0
    movq [r13+r15*8], xmm1
    inc r15
  \}

  macro make_pairs \{
  local loop
  local begin
  local jumptable
  local bucket2
  local bucket3
  local bucket4
  local bucket5
  local bucket6
  local bucket7
  local done

    mmap_allocate PairBlockSize
    mov r13, rax
    lea rsi, [r12+BucketBlockOffset]
    vzeroall
    xor r15, r15
    jmp begin
  loop:
    add rsi, BucketSize
  begin:
    vmovdqu ymm1, yword [rsi]
    vpcmpeqd ymm2, ymm1, ymm0
    vpmovmskb eax, ymm2
    popcnt eax, eax
    jmp [jumptable+rax*8]
  jumptable:
    dq loop
    dq loop
    dq bucket2
    dq bucket3
    dq bucket4
    dq bucket5
    dq bucket6
    dq bucket7
    dq bucket8
  bucket2:
    make_pair 0,1
  bucket3:
    make_pair 0,1
    make_pair 0,2
    make_pair 1,2
  bucket4:
    make_pair 0,1
    make_pair 0,2
    make_pair 1,2
    make_pair 0,3
    make_pair 1,3
    make_pair 2,3
  bucket5:
    make_pair 0,1
    make_pair 0,2
    make_pair 1,2
    make_pair 0,3
    make_pair 1,3
    make_pair 2,3
    make_pair 0,4
    make_pair 1,4
    make_pair 2,4
    make_pair 3,4
  bucket6:
    make_pair 0,1
    make_pair 0,2
    make_pair 1,2
    make_pair 0,3
    make_pair 1,3
    make_pair 2,3
    make_pair 0,4
    make_pair 1,4
    make_pair 2,4
    make_pair 3,4
    make_pair 0,5
    make_pair 1,5
    make_pair 2,5
    make_pair 3,5
    make_pair 4,5
  bucket7:
    make_pair 0,1
    make_pair 0,2
    make_pair 1,2
    make_pair 0,3
    make_pair 1,3
    make_pair 2,3
    make_pair 0,4
    make_pair 1,4
    make_pair 2,4
    make_pair 3,4
    make_pair 0,5
    make_pair 1,5
    make_pair 2,5
    make_pair 3,5
    make_pair 4,5
    make_pair 0,6
    make_pair 1,6
    make_pair 2,6
    make_pair 3,6
    make_pair 4,6
    make_pair 5,6
  bucket8:
    make_pair 0,1
    make_pair 0,2
    make_pair 1,2
    make_pair 0,3
    make_pair 1,3
    make_pair 2,3
    make_pair 0,4
    make_pair 1,4
    make_pair 2,4
    make_pair 3,4
    make_pair 0,5
    make_pair 1,5
    make_pair 2,5
    make_pair 3,5
    make_pair 4,5
    make_pair 0,6
    make_pair 1,6
    make_pair 2,6
    make_pair 3,6
    make_pair 4,6
    make_pair 5,6
    make_pair 0,7
    make_pair 1,7
    make_pair 2,7
    make_pair 3,7
    make_pair 4,7
    make_pair 5,7
    make_pair 6,7
  \} 
}

Equihash 200,9
Equihash 144,5

libeqh_oom:
    mov rax, SYSCALL_EXIT
    mov rdi, 42
    syscall

section 'data' writeable
stage:
    dq 0
