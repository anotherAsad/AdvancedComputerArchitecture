py.exe .\asm_converter.py
iverilog -g2012 code.sv
# iverilog code.v

if($?){
	Write-Host "Compilation Successful";
	vvp a.out;
}
else {
	Write-Host "Command Failed";
}