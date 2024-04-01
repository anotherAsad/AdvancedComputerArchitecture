asm = """
lw		x1, 580(x0)
lw		x2, 240(x0)
lw		x3, 98(x0)
lw		x4, 365(x0)
add		x1, x5, x7
add		x1, x1, x5
mul		x2, x5, x7
nop
"""

# https://riscvasm.lucasteske.dev/#

machine_code = """
24402083
0f002103
06202183
16d02203
007280b3
005080b3
02728133
00000013
"""

# Split the multi-line string into a list of lines
instructions = machine_code.splitlines()
instructions = instructions[1:]

# Create an empty list to store modified lines
modified_instructions = []

# Loop through each line in the instructions list
for i, line in enumerate(instructions):
  # Prepend "instr_mem[", index (i), "] = " to the line
  modified_instructions.append(f"instr_mem[8'h{hex(i)[2:]}] = 32'h{line};		// ")


asm = asm.splitlines()
asm = asm[1:]

# Print the modified instructions list
for idx in range(0, len(modified_instructions)):
	print(modified_instructions[idx] + asm[idx])