//===-------------------------------------------------------*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef TORCH_OPS
#define TORCH_OPS

include "npcomp/Dialect/Torch/IR/TorchTypes.td"
include "npcomp/Dialect/Torch/IR/OpInterfaces.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

class Torch_Op<string mnemonic, list<OpTrait> traits = []>
    : Op<Torch_Dialect, mnemonic, traits> {
}

// TODO: Add alias mapping from the signature and use it to implement the
// effects interface (since whether the kernel_call has side effects is
// dependent on its metadata).
def Torch_KernelCallOp : Torch_Op<"kernel_call", [
    DeclareOpInterfaceMethods<TorchKernelOpInterface>]> {
  let summary = "Calls a Torch custom kernel";
  let description = [{
    Torch kernel calls are matched by the runtime based on signature, including
    the fully qualified kernel name (i.e. "namespace::name") and the tuple of
    argument types. This op models such an invocation.
  }];

  let arguments = (ins
    StrAttr:$kernelName,
    Variadic<AnyTorchType>:$args,
    StrArrayAttr:$sigArgTypes,
    StrArrayAttr:$sigRetTypes,
    BoolAttr:$sigIsVararg,
    BoolAttr:$sigIsVarret,
    BoolAttr:$sigIsMutable
    // TODO: Add alias mapping.
  );
  let results = (outs
    Variadic<AnyTorchType>:$results
  );

  let assemblyFormat = [{
    $kernelName $args `:` functional-type($args, results) attr-dict
  }];
}

//===----------------------------------------------------------------------===//
// TorchScript `torch.nn.Module` object instantiation ops.
//===----------------------------------------------------------------------===//

def Torch_NnModuleOp : Torch_Op<"nn_module", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    SingleBlockImplicitTerminator<"::mlir::NPCOMP::Torch::NnModuleTerminatorOp">]> {
  let summary = "Constructs a torch.nn.Module";
  let description = [{
    This op is used to represent a torch.nn.Module when importing a
    graph of Python objects.

    This op returns a new torch.nn.Module as an SSA value, with a set of
    declaratively specified properties.

    Example:

    ```mlir
    %2 = torch.nn_module {
      torch.slot "b", %bool_true : !basicpy.BoolType
      torch.slot "i", %num3_i64 : i64
      torch.slot "f", %num : f64
      torch.slot "t", %0 : !numpy.ndarray<*:!numpy.any_dtype>
      torch.slot "submodule", %1 : !torch.nn.Module
    } : !torch.nn.Module<"my_class_name">
    ```

    This op is tightly coupled to the `torch.class_type` op named in the
    `!torch.nn.Module<"my_class_name">` type. Each slot must match precisely
    with the corresponding `torch.attr` in the `torch.class_type`.
    See the documentation for `torch.class_type` for information.
  }];

  let arguments = (ins);
  let results = (outs Torch_NnModuleType:$result);
  let regions = (region SizedRegion<1>:$region);
  let verifier = "return ::verify(*this);";

  let assemblyFormat = "$region attr-dict `:` type($result)";

  let extraClassDeclaration = [{
    StringRef getClassName() { return getType().getClassName(); }
  }];
}

def Torch_NnModuleTerminatorOp : Torch_Op<"nn_module_terminator", [Terminator,
    HasParent<"::mlir::NPCOMP::Torch::NnModuleOp">]> {
  let summary = "Implicit terminator for torch.nn_module";

  let arguments = (ins);
  let results = (outs);

  let assemblyFormat = "attr-dict";
}

def Torch_SlotOp : Torch_Op<"slot", [
    HasParent<"::mlir::NPCOMP::Torch::NnModuleOp">]> {
  let summary = "Define the value of a slot of a torch.nn.Module";
  let description = [{
    This op specifies that the initial value of the slot `name` of the
    parent torch.nn_module should be `value`, which is allowed to be an
    arbitrary Torch-compatible SSA value, including other !torch.nn.Module's.
  }];

  let arguments = (ins StrAttr:$name, AnyTorchType:$value);
  let results = (outs);

  let assemblyFormat = [{
    $name `,` $value attr-dict `:` type($value)
  }];
}

//===----------------------------------------------------------------------===//
// Modeling of TorchScript class types
//===----------------------------------------------------------------------===//

def Torch_ClassTypeOp : Torch_Op<"class_type", [
    Symbol,
    SingleBlockImplicitTerminator<"::mlir::NPCOMP::Torch::ClassTypeTerminatorOp">]> {
  let summary = "Constructs a torch.ClassType";
  let description = [{
    Declares a class type. Class types are the types used to describe
    TorchScript `torch.nn.Module`'s. The terminology "class type" is for
    consistency with TorchScript (a better name in our context might be
    "nn module subtype"). The `syn_name` of this op is the same string
    as in the `!torch.nn.Module<"...">` type.

    Example:

    ```mlir
    // A simple empty torch.class_type, with corresponding torch.nn_module.
    torch.class_type @empty {}
    %submodule = torch.nn_module {} : !torch.nn.Module<"empty">

    // A class type with many members.
    torch.class_type @test {
      torch.attr "b" : !basicpy.BoolType
      torch.attr "i" : i64
      torch.attr "f" : f64
      torch.attr "t" : !numpy.ndarray<*:!numpy.any_dtype>
      torch.attr "submodule" : !torch.nn.Module<"empty">
      torch.method "method", @f
    }
    torch.nn_module {
      // These must match the order and names in the `torch.class_type`.
      torch.slot "b", %bool_true : !basicpy.BoolType
      torch.slot "i", %num3_i64 : i64
      torch.slot "f", %num : f64
      torch.slot "t", %array : !numpy.ndarray<*:!numpy.any_dtype>
      torch.slot "submodule", %submodule : !torch.nn.Module<"empty">
    } : !torch.nn.Module<"test">
    ```
  }];

  let arguments = (ins SymbolNameAttr:$sym_name);
  let results = (outs);
  let regions = (region SizedRegion<1>:$region);
  let verifier = "return ::verify(*this);";

  let assemblyFormat = "$sym_name $region attr-dict";
}

def Torch_ClassTypeTerminatorOp : Torch_Op<"class_type_terminator", [Terminator,
    HasParent<"::mlir::NPCOMP::Torch::ClassTypeOp">]> {
  let summary = "Implicit terminator for torch.class_type";

  let arguments = (ins);
  let results = (outs);

  let assemblyFormat = "attr-dict";
}

def Torch_MethodOp : Torch_Op<"method", [
    HasParent<"::mlir::NPCOMP::Torch::ClassTypeOp">,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>
  ]> {
  let summary = "Declare a method of a torch.class_type";
  let description = [{
    This op declaratively specifies that the parent torch.class_type has a
    method `name` which calls `function`. `function` is an unbound function.
    That is, it explicitly takes the torch.nn.Module as a parameter (no implicit
    "self" object).

    If `private` is present, it indicates that external calls cannot be made
    to this method.
  }];

  // We don't use sym_visibility because that only applies to Symbol's, and
  // some of the related concepts like "nested" visibility are specific to
  // symbols.
  let arguments = (ins
    StrAttr:$name,
    FlatSymbolRefAttr:$function,
    // `private` is a C++ keyword, so use `isPrivate`.
    UnitAttr:$isPrivate
  );
  let results = (outs);

  let assemblyFormat = [{
    (`private` $isPrivate^)? $name `,` $function attr-dict
  }];
}

def Torch_AttrOp : Torch_Op<"attr", [
    HasParent<"::mlir::NPCOMP::Torch::ClassTypeOp">
  ]> {
  let summary = "Declare an attribute of a torch.class_type";
  let description = [{
    This op declaratively specifies that torch.nn.Module's of the parent
    torch.class_type must have an attribute `name` of type `type`.

    If `private` is present, it indicates that the value of this attribute
    cannot be accessed externally.
  }];

  // We don't use sym_visibility because that only applies to Symbol's, and
  // some of the related concepts like "nested" visibility are specific to
  // symbols.
  let arguments = (ins
    StrAttr:$name,
    TypeAttr:$type,
    // `private` is a C++ keyword, so use `isPrivate`
    UnitAttr:$isPrivate
  );
  let results = (outs);

  let assemblyFormat = [{
    (`private` $isPrivate^)? $name `:` $type attr-dict
  }];
}

//===----------------------------------------------------------------------===//
// Global slot ops
//===----------------------------------------------------------------------===//
// TODO: Should these be in a separate dialect?
// At this point, they are fairly specific to torch types, but their get/set
// semantics follow Python.
//===----------------------------------------------------------------------===//

def Torch_GlobalSlotOp : Torch_Op<"global_slot", [
    Symbol,
    IsolatedFromAbove,
    SingleBlockImplicitTerminator<"::mlir::NPCOMP::Torch::GlobalSlotInitOp">
  ]> {
  let summary = "A slot with global storage";
  let description = [{
    Represents a slot with global storage. The slot semantics are the same
    as Python's: getting or setting a slot is done by object identity.

    The `typeBound` is a type that the contained type is a subtype of.
  }];

  let arguments = (ins
    SymbolNameAttr:$sym_name,
    OptionalAttr<StrAttr>:$sym_visibility,
    TypeAttr:$typeBound
  );
  let results = (outs);
  let regions = (region SizedRegion<1>:$initializer);

  let assemblyFormat = [{
    ($sym_visibility^)? $sym_name attr-dict `:` $typeBound ($initializer^)?
  }];
}

def Torch_GlobalSlotInitOp : Torch_Op<"global_slot.init", [
    Terminator,
    HasParent<"::mlir::NPCOMP::Torch::GlobalSlotOp">]> {
  let summary = "yield-like terminator for torch.global_slot initializer region";
  let description = [{
    The operand to this op becomes the initial value of the parent
    torch.global_slot.
  }];

  let arguments = (ins AnyTorchType:$initialValue);
  let results = (outs);

  // This bulider creates an illegal op, but is needed to appease
  // ensureTerminator in the default builders for SingleBlockImplicitTerminator
  // on the parent torch.global_slot op.
  // TODO: Have a SingleBlockExplicitTerminator trait.
  let builders = [OpBuilderDAG<(ins), [{ /*nothing to do */ }]>];

  let assemblyFormat = "$initialValue attr-dict `:` type($initialValue)";
}

def Torch_GlobalSlotGetOp : Torch_Op<"global_slot.get", []> {
  let summary = "Get the value stored in a torch.global_slot";

  let arguments = (ins
    FlatSymbolRefAttr:$slot
  );
  let results = (outs AnyTorchType:$result);

  let assemblyFormat = [{
    $slot attr-dict `:` type($result)
  }];
}

def Torch_GlobalSlotSetOp : Torch_Op<"global_slot.set", []> {
  let summary = "Set the value stored in a torch.global_slot";

  let arguments = (ins
    FlatSymbolRefAttr:$slot,
    AnyTorchType:$value
  );
  let results = (outs);

  let assemblyFormat = [{
    $slot `=` $value attr-dict `:` type($value)
  }];
}

//===----------------------------------------------------------------------===//
// TorchScript `prim::` ops.
//===----------------------------------------------------------------------===//

def Torch_PrimGetAttrOp : Torch_Op<"prim.GetAttr", []> {
  let summary = "TorchScript prim::GetAttr op";

  let arguments = (ins StrAttr:$name, Torch_NnModuleType:$receiver);
  let results = (outs AnyTorchType:$result);

  let assemblyFormat = [{
    $receiver `[` $name `]` attr-dict `:` type($receiver) `->` type($result)
  }];
}

def Torch_PrimSetAttrOp : Torch_Op<"prim.SetAttr", []> {
  let summary = "TorchScript prim::SetAttr op";

  let arguments = (ins
    StrAttr:$name,
    Torch_NnModuleType:$receiver,
    AnyTorchType:$value
  );
  let results = (outs);

  let assemblyFormat = [{
    $receiver `[` $name `]` `=` $value attr-dict `:` type($receiver) `,` type($value)
  }];
}

def Torch_PrimCallMethodOp : Torch_Op<"prim.CallMethod", []> {
  let summary = "TorchScript prim::CallMethod op";

  let arguments = (ins
    StrAttr:$name,
    Torch_NnModuleType:$receiver,
    Variadic<AnyTorchType>:$operands
  );
  let results = (outs AnyTorchType:$result);

  let assemblyFormat = [{
    $receiver `[` $name `]` `(` $operands `)` attr-dict `:` type($receiver) `,` functional-type($operands, $result)
  }];
}

def Torch_PrimPrintOp : Torch_Op<"prim.Print", []> {
  let summary = "TorchScript prim::Print op";

  let arguments = (ins Variadic<AnyTorchType>:$operands);
  let results = (outs);

  let assemblyFormat = [{
    `(` $operands `)` attr-dict `:` type($operands)
  }];
}

def Torch_PrimLoopOp : Torch_Op<"prim.Loop", [
  DeclareOpInterfaceMethods<RegionBranchOpInterface, ["getSuccessorEntryOperands"]>]> {
  let summary = "TorchScript prim::Loop op";
  let description = [{
    This op (together with prim.Loop.condition) define a looping construct
    that combines `for` and `while` behavior.

    See: https://github.com/pytorch/pytorch/blob/master/torch/csrc/jit/OVERVIEW.md#loops
  }];

  let arguments = (ins
    I64:$maxTripCount,
    Basicpy_BoolType:$initialCondition,
    Variadic<AnyTorchType>:$iterArgsInit
  );
  let results = (outs Variadic<AnyTorchType>:$results);
  let regions = (region SizedRegion<1>:$region);

  let assemblyFormat = [{
    $maxTripCount `,` $initialCondition `,` `init` `(` $iterArgsInit `)` $region
    attr-dict `:` functional-type(operands, results)
  }];
  let verifier = [{ return RegionBranchOpInterface::verifyTypes(*this); }];
}

def Torch_PrimLoopConditionOp : Torch_Op<"prim.Loop.condition", [
    Terminator,
    HasParent<"::mlir::NPCOMP::Torch::PrimLoopOp">]> {
  let summary = "yield-like terminator for torch.prim.Loop";
  let description = [{
    Does not correspond to any torch prim op directly (the way that they model
    blocks has a built-in notion of yield-like terminator).
  }];

  let arguments = (ins Basicpy_BoolType:$shouldContinue, Variadic<AnyTorchType>:$iterArgs);
  let results = (outs);

  let assemblyFormat = [{
    $shouldContinue `iter` `(` $iterArgs `)`
    attr-dict `:` type($shouldContinue) `,` `(` type($iterArgs) `)`
  }];
}

def Torch_PrimNumToTensorOp : Torch_Op<"prim.NumToTensor", []> {
  let summary = "TorchScript prim::NumToTensor op";

  let arguments = (ins AnyTorchNumberType:$num);
  let results = (outs AnyTorchTensorType:$result);

  let assemblyFormat = [{
    $num attr-dict `:` type($num) `->` type($result)
  }];
}

def Torch_PrimRaiseExceptionOp : Torch_Op<"prim.RaiseException", []> {
  let summary = "TorchScript prim::RaiseException op";

  // TODO: Error messages suggest that any exception derived from BaseException
  // is allowed at the Python level, but they seem to just be strings at the
  // IR level.
  let arguments = (ins Basicpy_BytesType:$errorMsg);
  let results = (outs);

  let assemblyFormat = [{
    $errorMsg attr-dict
  }];
}

def Torch_PrimUninitializedOp : Torch_Op<"prim.Uninitialized", []> {
  let summary = "TorchScript prim::Uninitialized op";

  let arguments = (ins);
  let results = (outs AnyTorchType:$result);

  let assemblyFormat = [{
    attr-dict `:` type($result)
  }];
}

def Torch_Primunchecked_castOp : Torch_Op<"prim.unchecked_cast", [
    NoSideEffect
  ]> {
  let summary = "TorchScript prim::unchecked_cast op";
  let description = [{
    Refine a type to one of its subtypes.

    For example, refine a type that was only statically known to be
    Optional[T] to a T when we obtain static information that guarantees it.

    The key observation here is that Optional[T] does not have a corresponding
    runtime type (i.e. `c10::IValue` subclass). It represents a set of possible
    concrete types which for `Optional[T]` is either `None` or a concrete
    subtype of `T` (which in the simplest case is just `T`). In particular,
    at runtime there is no way to distinguish `Optional[int]` from
    `Optional[Optional[int]]`, because both are either `None` or `int`.
    This differs from C++ std::optional.

    The best documentation of this op is inspection of the code in
    `torch/csrc/jit/frontend/ir_emitter.cpp`.
  }];

  // TODO: When we model PyTorch's notion of subtyping, verify the types here.
  let arguments = (ins AnyTorchType:$operand);
  let results = (outs AnyTorchType:$result);

  let assemblyFormat = [{
    $operand attr-dict `:` type($operand) `->` type($result)
  }];
}

//===----------------------------------------------------------------------===//
// Additional ops used to model TorchScript's Graph's / Node's.
//===----------------------------------------------------------------------===//

def Torch_DerefineOp : Torch_Op<"derefine", [
    NoSideEffect
  ]> {
  let summary = "De-refine a type";
  let description = [{
    In terms of IR structure, TorchScript allows types to vary in many
    circumstances where MLIR requires pointer-identical types. In particular,
    it is valid to pass any subtype in place of a type. For example, if an
    `Optional[int]` is required somewhere in the IR, it is legal to pass a
    value of just `int` (but not the other way around; see
    `torch.prim.unchecked_cast`). In effect, every *use* can have a different
    type.

    This op bridges that impedance mismatch. This op allows casting a value
    from one type to a type that it is a subtype of to model this behavior.
  }];

  // TODO: When we model PyTorch's notion of subtyping, verify the types here.
  let arguments = (ins AnyTorchType:$operand);
  let results = (outs AnyTorchType:$result);

  let assemblyFormat = [{
    $operand attr-dict `:` type($operand) `->` type($result)
  }];
}

def Torch_PrimListUnpackOp: Torch_Op<"prim.ListUnpack", []> {
  let summary = "TorchScript prim::ListUnpack op";

  let arguments = (ins AnyTorchType:$operand);
  let results = (outs Variadic<AnyTorchType>:$results);

  let assemblyFormat = [{
    $operand attr-dict `:` type($operand) `->` type($results)
  }];
}

def Torch_PrimTupleUnpackOp: Torch_Op<"prim.TupleUnpack", []> {
  let summary = "TorchScript prim::TupleUnpack op";

  let arguments = (ins AnyTorchType:$operand);
  let results = (outs Variadic<AnyTorchType>:$results);

  let assemblyFormat = [{
    $operand attr-dict `:` type($operand) `->` type($results)
  }];
}

def Torch_PrimTupleIndexOp : Torch_Op<"prim.TupleIndex", []> {
  let summary = "TorchScript prim::TupleIndex op";
  let arguments = (ins 
      AnyTorchType:$operand,
      AnyTorchNumberType:$idx);
  let results = (outs AnyTorchType:$result);
  let assemblyFormat = [{
    $operand `,` $idx attr-dict `:` type($operand) `,` type($idx) `->` type($result)
  }];
}

#endif // TORCH_OPS
