/// Mips Reference impl. https://inst.eecs.berkeley.edu/~cs61c/resources/MIPS_help.html
module omo::mips {
    use signed_integer::bits;
    use signed_integer::bits::{Bits, se, left_shift};
    use signed_integer::i64;
    use trie::hash_value::HashValue;
    use trie::hash_value;
    use omo::memory::{Memory, read_reg, write_reg, read_reg_bits, write_reg_bits, read_memory, write_memory};


    const REG_ZERO: u64 = 2;
    const REG_R31: u64 = 33;
    const REG_PC: u64 = 1;
    const REG_SP: u64 = 31; // R29
    const REG_HI: u64 = 129;
    const REG_LO: u64 = 130;
    const REG_CP0_CONFIG3: u64 = 137;
    const REG_CP0_USERLOCAL: u64 = 138;

    const REG_R2: u64 = 4;
    const REG_R4: u64 = 6;
    const REG_V0: u64 = 4;
    const REG_A0: u64 = 6;
    /// vector[REG_A0, REG_A0 + 1, REG_A0 + 2, REG_A0 + 3];
    const ARG_REGS: vector<u64> = vector[6, 7,8,9];


    const EXIT_ADDRESS: u64 = 0xffffffff;
    fun get_pc(mem: &Memory, _state_hash: HashValue): u64 {
        read_reg(mem, _state_hash, REG_PC)
    }
    fun set_pc(mem: &mut Memory, state_hash: HashValue, next_pc: u64): HashValue {
        write_reg(mem, state_hash, REG_PC, next_pc)
    }

    public fun gpr(mem: &Memory, _state_hash: HashValue, id: u64): u64 {
        read_reg(mem, _state_hash, id + REG_ZERO)
    }
    public fun gpr_bits(mem: &Memory, _state_hash: HashValue, id: u64): Bits {
        read_reg_bits(mem, _state_hash, id + REG_ZERO)
    }
    public fun set_gpr(mem: &mut Memory, state_hash: HashValue, id: u64, v: u64): HashValue {
        write_reg(mem, state_hash, id + REG_ZERO, v)
    }
    public fun set_gpr_bits(mem: &mut Memory, state_hash: HashValue, id: u64, v: Bits): HashValue {
        write_reg_bits(mem, state_hash, id + REG_ZERO, v)
    }
    public fun get_sp(mem: &Memory, state_hash: HashValue): u64 {
        read_reg(mem, state_hash, REG_SP)
    }
    public fun set_sp(mem: &mut Memory, state_hash: HashValue, v: u64): HashValue {
        write_reg(mem, state_hash, REG_SP, v)
    }

    public fun step(mem: &mut Memory, state_hash: HashValue): HashValue {
        let pc = get_pc(mem, state_hash);
        if (pc == EXIT_ADDRESS) {
            return state_hash
        };
        let new_state = step_pc(mem, state_hash, pc, pc + 4);
        new_state
    }


    fun handle_rtype(mem: &mut Memory, state_hash: HashValue,  pc: u64, next_pc: u64, insn: Bits): HashValue {
        let funct = bits::data(&bits::slice(insn, 5, 0));
        let shamt = (bits::data(&bits::slice(insn, 10, 6)) as u8);
        let rd = bits::data(&bits::slice(insn, 15, 11));
        let rt = bits::data(&bits::slice(insn, 20, 16));
        let rs = bits::data(&bits::slice(insn, 25, 21));
        let rt_value = gpr_bits(mem, state_hash, rt);
        let rs_value = gpr_bits(mem, state_hash, rs);

        state_hash = if (funct == 0) {
            //sll
            let value = gpr(mem, state_hash, rt) << shamt;
            set_gpr(mem, state_hash, rd, value)
        } else if (funct == 2) {
            //srl
            let value = gpr(mem, state_hash, rt) >> shamt;
            set_gpr(mem, state_hash, rd, value)
        } else if (funct == 3) {
            //sra
            let value = bits::se(bits::from_u64(gpr(mem, state_hash, rt) >> shamt, 32 - shamt), 32);

            set_gpr(mem, state_hash, rd, bits::data(&value))
        } else if (funct == 4) {
            // sllv
            let rt_value = gpr(mem, state_hash, rt);
            let rs_value = bits::slice(gpr_bits(mem, state_hash, rs), 4, 0); // lower 5-bits
            set_gpr(mem, state_hash, rd, rt_value << (bits::data(&rs_value) as u8))
        } else if (funct == 6) {
            // srlv
            let rt_value = gpr(mem, state_hash, rt);
            let rs_value = bits::slice(gpr_bits(mem, state_hash, rs), 4, 0); // lower 5-bits
            set_gpr(mem, state_hash, rd, rt_value >> (bits::data(&rs_value) as u8))
        } else if (funct == 7) {
            // srav
            let rt_value = gpr(mem, state_hash, rt);
            let rs_value = (bits::data(&bits::slice(gpr_bits(mem, state_hash, rs), 4, 0)) as u8); // lower 5-bits
            set_gpr(mem, state_hash, rd, bits::data(&se(bits::from_u64(rt_value >> rs_value, 32 - rs_value), 32)))
        } else if (funct == 8) {
            // jr
            let rs_value = gpr_bits(mem, state_hash, rs);
            return step_pc(mem, state_hash, next_pc, bits::data(&rs_value))
        } else if (funct == 9) {
            // jalr
            let rs_value = gpr_bits(mem, state_hash, rs);
            let state_hash = step_pc(mem, state_hash, next_pc, bits::data(&rs_value));
            return set_gpr(mem, state_hash, 31, pc + 8)
        } else if (funct == 12) {
            // syscall
            // TODO: handle syscall
            let exit = handle_syscall(mem, state_hash);
            if (exit) {
                next_pc = 0x5ead0000;
            };
            state_hash
        } else if (funct == 16) {
            // mfhi
            let val = read_reg_bits(mem, state_hash, REG_HI);
            set_gpr(mem, state_hash, rd, bits::data(&val))
        } else if (funct == 17) {
            // mthi
            let val = bits::data(&rs_value);
            write_reg(mem, state_hash, REG_HI, val)
        } else if (funct == 18) {
            // mflo
            let val = read_reg_bits(mem, state_hash, REG_LO);
            set_gpr(mem, state_hash, rd, bits::data(&val))
        } else if (funct == 19) {
            // mtlo
            let val = bits::data(&rs_value);
            write_reg(mem, state_hash, REG_LO, val)
        } else if (funct == 24) {
            // mult
            let val = i64::mul(
                i64::from_bits(rs_value),
                i64::from_bits(rt_value),
            );
            let val = bits::data(&i64::to_bits(val));
            let hi = val >> 32;
            let lo = val & 0xffffffff;
            state_hash = write_reg(mem, state_hash, REG_HI, hi);
            write_reg(mem, state_hash, REG_LO, lo)
        } else if (funct == 25) {
            // multu
            let v = bits::data(&rs_value) * bits::data(&rt_value);
            let hi = v >> 32;
            let lo = (v << 32) >> 32;
            state_hash = write_reg(mem, state_hash, REG_HI, hi);
            write_reg(mem, state_hash, REG_LO, lo)
        } else if (funct == 26) {
            // div
            let rs_value = i64::from_bits(rs_value);
            let rt_value = i64::from_bits(rt_value);
            let lo = bits::slice(i64::to_bits(i64::div(rs_value, rt_value)), 31, 0);
            let hi = bits::slice(i64::to_bits(i64::rem(rs_value, rt_value)), 31, 0);
            state_hash = write_reg_bits(mem, state_hash, REG_HI, hi);
            write_reg_bits(mem, state_hash, REG_LO, lo)
        } else if (funct == 27) {
            // divu
            let rs_value = bits::data(&rs_value);
            let rt_value = bits::data(&rt_value);
            let hi = rs_value % rt_value;
            let lo = rs_value / rt_value;
            state_hash = write_reg(mem, state_hash, REG_HI, hi);
            write_reg(mem, state_hash, REG_LO, lo)
        } else if (funct == 32) {
            // add
            addi(mem, state_hash, rd, rs_value, rt_value)
        }else if (funct == 33) {
            //addu
            addu(mem, state_hash, rd, rs_value, rt_value)
        }else if (funct == 34) {
            //sub
            let temp = i64::sub(i64::from_bits(rs_value), i64::from_bits(rt_value));
            let temp = i64::to_bits(temp);
            let bit_32 = bits::bit(&temp, 32);
            let bit_31 = bits::bit(&temp, 31);
            if (bit_31 != bit_32) {
                abort 1000
            };
            set_gpr_bits(mem, state_hash, rd, bits::slice(temp, 31, 0))
        }else if (funct == 35) {
            //subu
            let temp = bits::data(&rs_value) - bits::data(&rt_value);
            set_gpr_bits(mem, state_hash, rd, bits::from_u64(temp, 32))
        }else if (funct == 36) {
            //and
            let temp = bits::data(&rs_value) & bits::data(&rt_value);
            set_gpr_bits(mem, state_hash, rd, bits::from_u64(temp, 32))
        }else if (funct == 37) {
            //or
            let temp = bits::data(&rs_value) | bits::data(&rt_value);
            set_gpr_bits(mem, state_hash, rd, bits::from_u64(temp, 32))
        }else if (funct == 38) {
            //xor
            let temp = bits::data(&rs_value) ^ bits::data(&rt_value);
            set_gpr_bits(mem, state_hash, rd, bits::from_u64(temp, 32))
        }else if (funct == 39) {
            // nor
            let temp = bits::data(&rs_value) | bits::data(&rt_value);
            temp = temp ^ 0xffffffff;  // not
            set_gpr_bits(mem, state_hash, rd, bits::from_u64(temp, 32))
        }else if (funct == 42) {
            // slt
            let temp = i64::less_than(
                i64::from_bits(rs_value), i64::from_bits(rt_value));
            let temp = if (temp) { 1 } else { 0 };
            set_gpr_bits(mem, state_hash, rd, bits::from_u64(temp, 32))
        }else if (funct == 43) {
            // sltu
            let temp = if (bits::data(&rs_value) < bits::data(&rt_value)) { 1 } else { 0 };
            set_gpr_bits(mem, state_hash, rd, bits::from_u64(temp, 32))
        } else {
            abort 502
        };
        return set_pc(mem, state_hash, next_pc)
    }
    fun handle_jtype(mem: &mut Memory, state_hash: HashValue, pc: u64, next_pc: u64, insn: Bits, opcode: u64): HashValue {
        if (opcode == 3) {
            state_hash = set_gpr(mem, state_hash, 31, pc + 8);
        };
        let jump_address = bits::slice(insn, 25, 0);
        let higher = bits::slice(bits::from_u64(pc + 4, 32), 31, 28);
        let new_pc = bits::concat(higher, bits::concat(jump_address, bits::repeat_bit(false, 2)));

        let state_hash = step_pc(mem, state_hash, next_pc, bits::data(&new_pc));

        return state_hash
    }
    fun handle_itype(mem: &mut Memory, state_hash: HashValue, pc: u64, next_pc: u64, insn: Bits, opcode: u64): HashValue {
        let rs = bits::data(&bits::slice(insn, 25, 21));
        let rt = bits::data(&bits::slice(insn, 20, 16));
        let rs_value = gpr_bits(mem, state_hash, rs);
        let rt_value = gpr_bits(mem, state_hash, rt);
        let imm = bits::slice(insn, 15, 0);

        // branch insr
        if (opcode >= 4 && opcode < 8) {
            // beq, bne, blez, bgtz

            let should_branch = if (opcode == 4) {
                rs_value == rt_value
            } else if (opcode == 5) {
                rs_value != rt_value
            } else if (opcode == 6) {
                // rs <= 0
                !i64::less_than(
                    i64::zero(),
                    i64::from_bits(rs_value)
                )
            } else if (opcode == 7) {
                // rs > 0
                i64::less_than(
                    i64::zero(),
                    i64::from_bits(rs_value)
                )
            } else {
                false
            };
            if (should_branch) {
                return step_pc(mem, state_hash, next_pc, (pc + 4 + bits::data(&se(bits::left_shift(imm, 2), 32))) & 0xffffffff)
            } else {
                return step_pc(mem, state_hash, next_pc, next_pc + 4)
            }
        };

        state_hash = if (opcode == 8) {
            // addi
            addi(mem, state_hash, rt, rs_value, se(imm, 32))
        } else if (opcode == 9) {
            // addiu
            addu(mem, state_hash, rt, rs_value, se(imm, 32))
        } else if (opcode == 10) {
            //slti
            let temp = i64::less_than(i64::from_bits(rs_value), i64::from_bits(se(imm, 32)));
            set_gpr(mem, state_hash, rt, if (temp) { 1 } else { 0 })
        } else if (opcode == 11) {
            // sltiu
            let temp = bits::data(&rs_value) < bits::data(&se(imm, 32));
            set_gpr(mem, state_hash, rt, if (temp) { 1 } else { 0 })
        } else if (opcode == 12) {
            // andi
            let temp = bits::data(&rs_value) & bits::data(&imm);
            set_gpr(mem, state_hash, rt, temp & 0xffffffff)
        } else if (opcode == 13) {
            // ori
            let temp = bits::data(&rs_value) | bits::data(&imm);
            set_gpr(mem, state_hash, rt, temp & 0xffffffff)
        } else if (opcode == 14) {
            // xori
            let temp = bits::data(&rs_value) ^ bits::data(&imm);
            set_gpr(mem, state_hash, rt, temp & 0xffffffff)
        } else if (opcode == 15) {
            // lui
            set_gpr_bits(mem, state_hash, rt, left_shift(imm, 16))
        } else if (opcode == 32) {
            // lb
            let mem_addr = (bits::data(&se(imm, 32)) + bits::data(&rs_value)) & 0xffffffff;
            let memory_data_4b = bits::from_u64(read_memory(mem, state_hash, mem_addr & 0xfffffffc), 32);

            let mem_1b = bits::slice(memory_data_4b, (31 - (mem_addr & 0x3) * 8 as u8), (32 - (mem_addr & 0x3) * 8 - 8 as u8));
            set_gpr_bits(mem, state_hash, rt, se(mem_1b, 32))
        } else if (opcode == 33) {
            // lh
            let mem_addr = (bits::data(&se(imm, 32)) + bits::data(&rs_value)) & 0xffffffff;
            // must be a mutiple 0f 2
            assert!(mem_addr & 0x1 == 0, 10000);
            let memory_data_4b = bits::from_u64(read_memory(mem, state_hash, mem_addr & 0xfffffffc), 32);
            let mem_2b = bits::slice(memory_data_4b, (31 - (mem_addr & 0x3) * 8 as u8), (32 - (mem_addr & 0x3) * 8 - 16 as u8));
            set_gpr_bits(mem, state_hash, rt, se(mem_2b, 32))
        }
        // else if (opcode == 34) { // lwl
        //
        // }
        else if (opcode == 35) {
            // lw
            let mem_addr = (bits::data(&se(imm, 32)) + bits::data(&rs_value)) & 0xffffffff;
            // must be a multiple of 4
            assert!(mem_addr & 0x3 == 0, 10000);
            let memory_data_4b = bits::from_u64(read_memory(mem, state_hash, mem_addr & 0xfffffffc), 32);
            set_gpr_bits(mem, state_hash, rt, memory_data_4b)
        } else if (opcode == 36) {
            // lbu
            let mem_addr = (bits::data(&se(imm, 32)) + bits::data(&rs_value)) & 0xffffffff;
            let memory_data_4b = bits::from_u64(read_memory(mem, state_hash, mem_addr & 0xfffffffc), 32);

            let mem_1b = bits::slice(memory_data_4b, (31 - (mem_addr & 0x3) * 8 as u8), (32 - (mem_addr & 0x3) * 8 - 8 as u8));
            set_gpr_bits(mem, state_hash, rt, bits::ze(mem_1b, 32))
        } else if (opcode == 37) {
            // lhu
            let mem_addr = (bits::data(&se(imm, 32)) + bits::data(&rs_value)) & 0xffffffff;
            // must be a mutiple 0f 2
            assert!(mem_addr & 0x1 == 0, 10000);
            let memory_data_4b = bits::from_u64(read_memory(mem, state_hash, mem_addr & 0xfffffffc), 32);
            let mem_2b = bits::slice(memory_data_4b, (31 - (mem_addr & 0x3) * 8 as u8), (32 - (mem_addr & 0x3) * 8 - 16 as u8));
            set_gpr_bits(mem, state_hash, rt, bits::ze(mem_2b, 32))
        } else if (opcode == 40) {
            // sb
            let mem_addr = (bits::data(&se(imm, 32)) + bits::data(&rs_value)) & 0xffffffff;
            let read_addr = mem_addr & 0xfffffffc;
            let memory_data_4b = bits::from_u64(read_memory(mem, state_hash, read_addr), 32);

            let write_back = bits::write_range(
                memory_data_4b,
                (31 - (mem_addr & 0x3) * 8 as u8), (32 - (mem_addr & 0x3) * 8 - 8 as u8),
                bits::slice(rt_value, 7, 0)
            );
            write_memory(mem, state_hash, read_addr, bits::data(&write_back))
        } else if (opcode == 41) {
            // sh
            let mem_addr = (bits::data(&se(imm, 32)) + bits::data(&rs_value)) & 0xffffffff;
            assert!(mem_addr & 0x1 == 0, 10000);
            let read_addr = mem_addr & 0xfffffffc;
            let write_back = {
                let memory_data_4b = bits::from_u64(read_memory(mem, state_hash, read_addr), 32);
                bits::write_range(
                    memory_data_4b,
                    (31 - (mem_addr & 0x3) * 8 as u8), (32 - (mem_addr & 0x3) * 8 - 16 as u8),
                    bits::slice(rt_value, 15, 0)
                )
            };
            write_memory(mem, state_hash, read_addr, bits::data(&write_back))
        } else if (opcode == 43) {
            let mem_addr = (bits::data(&se(imm, 32)) + bits::data(&rs_value)) & 0xffffffff;
            assert!(mem_addr & 0x3 == 0, 10000);

            let read_addr = mem_addr & 0xfffffffc;
            let write_back = rt_value;
            write_memory(mem, state_hash, read_addr, bits::data(&write_back))
        } else {
            abort opcode
        };

        return set_pc(mem, state_hash, next_pc)
    }

    fun step_pc(mem: &mut Memory, state_hash: HashValue, pc: u64, next_pc: u64): HashValue {
        pc = pc & 0xffffffff;
        next_pc = next_pc & 0xffffffff;

        let insn = read_memory(mem, state_hash, pc);
        let insn = bits::from_u64(insn, 32);
        let opcode = bits::slice(insn, 31, 26); // first 6-bits
        let opcode = bits::data(&opcode);

        // r-type
        state_hash = if (opcode == 0) {
            handle_rtype(mem, state_hash, pc, next_pc, insn)
        } else if (opcode == 2 || opcode == 3) {// j-type j/jal
            handle_jtype(mem, state_hash, pc, next_pc, insn, opcode)
        } else if (opcode >=4 && opcode <=43) { // i-types insts
             handle_itype(mem, state_hash, pc, next_pc, insn, opcode)
        }else {
            abort 1200
        };

        return state_hash
    }

    fun addi(mem: &mut Memory, state_hash: HashValue, store_reg: u64, a: Bits, b: Bits): HashValue {
        let val = i64::add(
            i64::from_bits(a),
            i64::from_bits(b),
        );
        let temp = i64::to_bits(val);
        let bit_32 = bits::bit(&temp, 32);
        let bit_31 = bits::bit(&temp, 31);
        if (bit_31 != bit_32) {
            abort 1000
        };
        set_gpr_bits(mem, state_hash, store_reg, bits::slice(temp, 31, 0))
    }

    fun addu(mem: &mut Memory, state_hash: HashValue, store_reg: u64, a: Bits, b: Bits): HashValue {
        let temp = bits::data(&a) + bits::data(&b);
        // only need last 32 bits
        let temp = temp & 0xffffffff;
        set_gpr(mem, state_hash, store_reg, temp)
    }


    fun stack_read(mem: &Memory, state_hash: HashValue, offset: u64): u64 {
        let addr = get_sp(mem, state_hash);
        let data = read_memory(mem, state_hash, addr + offset);
        data
    }
    fun get_param(mem: &Memory, state_hash: HashValue, index: u64): u64 {
        // only 4 regs for params
        if (index < 4) {
            let v = read_reg(mem,state_hash, REG_A0 + index);
            v
        } else {
            let si = index - 4;
            let offset = (4 + si) * 4;
            stack_read(mem, state_hash, offset)
        }
    }
    fun set_retvalue(mem: &mut Memory, retvalue: u64) {
        write_reg(mem, hash_value::zero(), REG_V0,  retvalue);
        write_reg(mem, hash_value::zero(), REG_A0 + 3, 0);
    }

    fun handle_syscall(mem: &mut Memory, state_hash: HashValue): bool {
        let sysno = read_reg(mem, state_hash, REG_V0);

        let ret_value = if (sysno == 4000) { // syscall
            0
        } else if (sysno == 4001) { // exit
            0
        } else if (sysno == 4283) { // set_thread_area
            let p0 = get_param(mem, state_hash, 0);
            set_thread_area(mem, p0)
        } else if (sysno == 4252) {
            let p0 = get_param(mem, state_hash, 0);
            set_tid_address(mem, p0)
        } else if (sysno == 4188) {
            poll(mem)
        } else if (sysno == 4194){
            let p0 = get_param(mem, state_hash, 0);
            let p1 = get_param(mem, state_hash, 1);
            let p2 = get_param(mem, state_hash, 2);
            rt_sigaction(mem, p0, p1, p2)
        } else if (sysno == 4195) {
            let p0 = get_param(mem, state_hash, 0);
            let p1 = get_param(mem, state_hash, 1);
            let p2 = get_param(mem, state_hash, 2);
            let p3 = get_param(mem, state_hash, 3);

            rt_sigprocmask(mem, p0,p1,p2,p3)
        } else if (sysno == 4206) {
            let p0 = get_param(mem, state_hash, 0);
            let p1 = get_param(mem, state_hash, 1);
            sigaltstack(mem, p0, p1)
        } else if (sysno == 4119) {
            sigreturn(mem)
        } else if (sysno == 4045) {
            let p0 = get_param(mem, state_hash, 0);
            brk(mem, p0)
        } else if (sysno == 4353) {
            let p0 = get_param(mem, state_hash, 0);
            let p1 = get_param(mem, state_hash, 1);
            getrandom(mem, p0, p1)
        }
        else {0};
        set_retvalue(mem, ret_value);
        false
    }

    fun set_thread_area(mem: &mut Memory, u_info_addr: u64): u64 {
        write_reg(mem, hash_value::zero(), REG_CP0_CONFIG3, 1 << 13);
        write_reg(mem, hash_value::zero(), REG_CP0_USERLOCAL, u_info_addr);
        write_reg(mem, hash_value::zero(), REG_V0, 0);
        write_reg(mem, hash_value::zero(), REG_A0 + 3, 0);
        0
    }
    fun set_tid_address(_mem: &mut Memory, _tidptr: u64): u64 {
        42
    }
    fun poll(_mem: &mut Memory): u64 {
        0
    }
    fun rt_sigaction(_mem: &mut Memory, _signum: u64, _act: u64, _oldact: u64): u64 {
        // TODO
        0
    }
    fun rt_sigprocmask(_mem: &mut Memory,
                       _how: u64,
                       _nset: u64,
                       _oset: u64,
                       _sigsetsize: u64,) : u64 {
        0
    }
    fun sigaltstack(_mem: &mut Memory, _ss: u64,
                    _oss: u64,): u64 {
        0
    }
    fun sigreturn(_mem: &mut Memory): u64 {
        0
    }

    fun brk(_mem: &mut Memory, _inp: u64): u64 {
        // TODO
        0
    }
    fun getrandom(_mem: &mut Memory, _buf: u64, _buf_len: u64): u64 {
        0
    }


}

//module omo::utils {
//    /// SignExt_idx(dat)
//    public fun se(dat: u64, idx: u64): u64 {
//        0
//    }
//}

