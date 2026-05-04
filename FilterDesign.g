################################################################################
# File   : FilterDesign.g
# Author : Sandeep Koranne (C) 2026. All rights reserved.
# Purpose: Design a DFT filter in fixed point, generate C code, convert it to
#        : Verilog using ICSC, run Yosys and do an effort estimation.
#        : Perform research in fixed precision methods.
#        : Tools used SPIRAL, SPL, GAP, ICSC, SystemC, Yosys
################################################################################
comment("");
comment("Fixed point analysis example with DFT");


if not IsBound(SpiralDefaults) then
    Load(spiral);
    Load(spiral.code);
fi;
Import(dft);
Import(filtering);
Import(paradigms.smp);


bits := 14; 
scale_val := 2^bits;
OldQuantizeFormula := function(f, scale)
    local func;
    func := x -> x; # Default: return as is
    
    # If the node is a Value (constant) and it's a Real number
    if IsValue(f) and (IsReal(f.v) or IsFloat(f.v)) then
        return V(Int(f.v * scale));
    fi;
    
    # If it's a structural node (like Sum or Product), recurse into children
    if IsBound(f.children) then
        f.children := List(f.children, c -> OldQuantizeFormula(c, scale));
    fi;
    
    return f;
end;
QuantizeFormula := function(f, scale)
    local new_children;

    # Debug: Print the type of the current node
    # Print("Visiting: ", f, "\n");

    # CASE 1: The node is a constant Value
    if IsValue(f) then
        if IsReal(f.v) or IsFloat(f.v) then
            Print("  QUANTIZING: ", f.v, " -> ", Int(f.v * scale), "\n");
            return V(Int(f.v * scale));
        else
            return f;
        fi;
    fi;

    # CASE 2: The node has children (Sum, Product, Compose, etc.)
    if IsBound(f.children) and Length(f.children) > 0 then
        # Map the function recursively to every child
        new_children := List(f.children, c -> QuantizeFormula(c, scale));
        
        # VERY IMPORTANT: Create a COPY of the node with new children
        # Simply assigning f.children := new_children often fails in GAP
        f := Copy(f);
        f.children := new_children;
        return f;
    fi;

    # CASE 3: Leaf node that isn't a value (like an Input/Output variable)
    return f;
end;

SimpleQuantizeICode := function(f, scale)
    local i;

    # Debug: See what node type we are hitting
    # Print("Node: ", IsBound(f.kind) and f.kind, " Type: ", TypeObj(f), "\n");

    # 1. If it's a Value node with a float, scale it and change type to TInt
    if IsValue(f) and (IsReal(f.v) or IsFloat(f.v)) then
        Print("  Quantizing Const: ", f.v, " -> ", Int(f.v * scale), "\n");
        f.v := Int(f.v * scale);
        f.t := TInt; # Change the type of the value itself
        return f;
    fi;

    # 2. Handle 'chain', 'program', 'func' (nodes with .cmds or .args)
    # Most ICode nodes store their sub-commands in .cmds
    if IsBound(f.cmds) then
        for i in [1..Length(f.cmds)] do
            f.cmds[i] := SimpleQuantizeICode(f.cmds[i], scale);
        od;
    fi;
    
    # 3. Handle 'decl' (nodes with a .body)
    if IsBound(f.body) then
        f.body := SimpleQuantizeICode(f.body, scale);
    fi;

    # 4. Handle 'assign', 'exp' (nodes with .args)
    if IsBound(f.args) then
        for i in [1..Length(f.args)] do
            f.args[i] := SimpleQuantizeICode(f.args[i], scale);
        od;
    fi;
    
    # 5. Fix type definitions in declarations
    if IsBound(f.vars) then
        for i in [1..Length(f.vars)] do
            if IsBound(f.vars[i].t) then f.vars[i].t := TInt; fi;
        od;
    fi;

    return f;
end;

QuantizeICode := function(f, scale)
    local n, name;

    # 1. Catch the Constants immediately
    if IsValue(f) then
        if IsReal(f.v) or IsFloat(f.v) then
            Print(">>> FOUND CONSTANT: ", f.v, " -> ", Int(f.v * scale), "\n");
            f.v := Int(f.v * scale);
            f.t := TInt; 
            return f;
        fi;
    fi;

    # 2. Generic Recursion: Look into EVERY field of the record
    if IsRec(f) then
        n := RecNames(f);
        for name in n do
            # We skip fields that aren't part of the tree structure
            if not name in ["type", "kind", "ops"] then
                
                # If the field is a single sub-node
                if IsRec(f.(name)) then
                    f.(name) := QuantizeICode(f.(name), scale);
                
                # If the field is a list of sub-nodes (like .cmds or .args)
                elif IsList(f.(name)) then
                    for i in [1..Length(f.(name))] do
                        if IsRec(f.(name)[i]) then
                            f.(name)[i] := QuantizeICode(f.(name)[i], scale);
                        fi;
                    od;
                fi;
            fi;
        od;
    fi;

    return f;
end;

opts := Copy(SpiralDefaults);
#opts.generate_fixed := true;
opts.frac := 12;
opts.width := 16;
#opts.precision := "fixed";
opts.useDeref := false;
my_type := TInt; 
opts.type := my_type;
opts.target := 'C';
t := DFT(16);
rt := RandomRuleTree(t, opts);
Import(compiler);
# rt := RandomRuleTree(t, opts);
rt := RuleTreeMid(t, opts);
formula := SumsRuleTree(rt, opts);
prog := CodeRuleTree(rt, opts);
# 3. Apply our manual quantization
#f_fixed := QuantizeFormula(prog, scale_val);
#DOES NOT WORK f_fixed := QuantizeFormula(formula, scale_val);
#f_fixed.type := TInt;
prog.type := TInt;
PrintTo( "DFT_float.c", PrintCode("DFT_16", prog, opts) );
#PrintTo( "DFT_fixed.c", PrintCode("DFT_16", f_fixed, opts) );




