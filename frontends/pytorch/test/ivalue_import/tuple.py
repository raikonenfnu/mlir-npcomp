# -*- Python -*-
# This file is licensed under a pytorch-style license
# See frontends/pytorch/LICENSE for license information.

import typing

import torch
import torch_mlir

# RUN: %PYTHON %s | npcomp-opt | FileCheck %s

mb = torch_mlir.ModuleBuilder()

class TestModule(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.t = (1, 2)
# CHECK: torch.class_type @[[CLASSTYPE:.*]] {
# TODO: Don't lose element type.
# CHECK: }
# CHECK: %[[N1:.*]] = basicpy.numeric_constant 1 : i64
# CHECK: %[[N2:.*]] = basicpy.numeric_constant 2 : i64
# CHECK: %[[TUPLE:.*]] = basicpy.build_tuple %[[N1]], %[[N2]] : (i64, i64) -> !basicpy.TupleType
# CHECK: torch.nn_module  {
# CHECK:   torch.slot "t", %[[TUPLE]] : !basicpy.TupleType
# CHECK: } : !torch.nn.Module<"[[CLASSTYPE]]">


test_module = TestModule()
recursivescriptmodule = torch.jit.script(test_module)
# TODO: Automatically handle unpacking Python class RecursiveScriptModule into the underlying ScriptModule.
mb.import_module(recursivescriptmodule._c)
mb.module.operation.print()
