This is the repository for experiments in Digital Filter design using SPIRAL SPL GAP Julia and C++.
```
     _____       _            __   
    / ___/____  (_)________ _/ /  
    \__ \/ __ \/ / ___/ __ `/ / 
   ___/ / /_/ / / /  / /_/ / /  
  /____/ .___/_/_/   \__,_/_/  
      /_/              
http://www.spiral.net  
Spiral 8.5.3
```
---------------------------------------------------------- 
The goal is to use Spiral to generate iCode for Filters and then try to understand how 
Spiral/GAP programming is done. In the short term, we wrote a C-2-Verilog (expression)
translator and then used Yosys to perform TECHMAP analysis.

Step 0: Run SPIRAL < FilterDesign.g to get the C-code for the required filter
There is still a need to remove the init and destroy functions, and also to have the X and Y
input as symbols. Also remove the temporary decls, we dont need them. I will add support to
handle this if time permits.
Step 1: make -f Makefile.c2v
Step 2: ./c2v DFT_float.c SDT_16 32 32 > SDT_16.v
This tells the program to read the C code with a vector 
Step 3: Use Yosys to read the Verilog (using -sv reader)
yosys> read_verilog -sv SDT_16.v 
1. Executing Verilog-2005 frontend: SDT_16.v
Parsing SystemVerilog input from `SDT_16.v' to AST representation.
Generating RTLIL representation for module `\SDT_16'.
Warning: Replacing memory \X with list of registers. See SDT_16.v:23
Warning: Replacing memory \Y with list of registers. See SDT_16.v:240
Successfully finished Verilog frontend.
> proc; opt; techmap; check
5. Executing CHECK pass (checking for obvious problems).
Checking module SDT_16...
Found and reported 0 problems.

=== SDT_16 ===

   Number of wires:              56176
   Number of wire bits:          62035
   Number of public wires:          95
   Number of public wire bits:    5954
   Number of memories:               0
   Number of memory bits:            0
   Number of processes:              0
   Number of cells:              58103
     $_ANDNOT_                   16951
     $_AND_                        353
     $_NAND_                       559
     $_NOR_                       7531
     $_NOT_                       2868
     $_ORNOT_                     2644
     $_OR_                        7662
     $_SDFF_PP0_                  1024
     $_XNOR_                      5764
     $_XOR_                      12747


read_liberty -overwrite -setattr liberty_cell -ignore_miss_func $PDK/sky130_fd_sc_hd__ff_n40C_1v65.lib
abc -liberty $PDK/sky130_fd_sc_hd__ff_n40C_1v65.lib
dfflibmap -liberty $PDK/sky130_fd_sc_hd__ff_n40C_1v65.lib 

```
This one did not route correctly due to pin access problem for clkbuf_16
Cell type report:                     Count       Area 
Fill cell                               788    2957.84 
Tap cell                              16434   20562.22
Buffer                                   28     140.13
Clock buffer                            285    4108.94
Timing Repair Buffer                   4347   37075.56
Inverter                                704    2642.53
Clock inverter                          105    1317.51
Sequential cell                        1024   21780.89
Multi-Input combinational cell        36907  386015.22
Total                                 60622  476600.85 
```
Reenabled ALUMAC sharing
```
{
  "DESIGN_NAME": "SDT_16",
  "VERILOG_FILES": "dir::src/*.v",
  "CLOCK_PORT": "clk",
  "CLOCK_PERIOD": 5.0,
  "DRT_THREADS": 32,
  "pdk::sky130A": {
    "FP_SIZING": "relative",
    "PL_TARGET_DENSITY": 0.30
  }
}
```


