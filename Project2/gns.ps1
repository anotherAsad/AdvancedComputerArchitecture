iverilog -g2005-sv code.sv
# iverilog code.v

if($?){
	Write-Host "Compilation Successful";
	vvp a.out;
}
else {
	Write-Host "Command Failed";
}