//===- node_importer.h ------------------------------------------*- C++ -*-===//
//
// This file is licensed under a pytorch-style license
// See frontends/pytorch/LICENSE for license information.
//
//===----------------------------------------------------------------------===//

#ifndef NPCOMP_FRONTENDS_PYTORCH_CSRC_NODE_IMPORTER_H
#define NPCOMP_FRONTENDS_PYTORCH_CSRC_NODE_IMPORTER_H

#include <memory>

#include "../pybind.h"
#include "func_builder.h"

#include "mlir-c/IR.h"

#include <torch/csrc/jit/api/compilation_unit.h>
#include <torch/csrc/jit/ir/ir.h>

namespace torch_mlir {

using CreateTerminatorFn =
    std::function<void(c10::ArrayRef<MlirValue>, MlirBlock)>;

MlirBlock importBlock(MlirContext context, torch::jit::Block *jitBlock,
                      CreateTerminatorFn createTerminator);

} // namespace torch_mlir

#endif // NPCOMP_FRONTENDS_PYTORCH_CSRC_NODE_IMPORTER_H
