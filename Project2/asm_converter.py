asm = """
lw		x1, 11(x0)		# w0
lw		x2, 15(x0)		# w1
lw		x3, 22(x0)		# w2
lw		x4, 45(x0)		# a1
lw		x5, 62(x0)		# a2
lw		x6, 79(x0)		# a3
mul		x10, x1, x4
mul		x11, x2, x5
add		x16, x10, x11
mul		x12, x3, x6
add		x16, x16, x12
add		x17, x1, x2
add		x17, x17, x3
div		x16, x16, x17
"""

# https://riscvasm.lucasteske.dev/#

machine_code = """
00b02083
00f02103
01602183
02d02203
03e02283
04f02303
02408533
025105b3
00b50833
02618633
00c80833
002088b3
003888b3
03184833
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