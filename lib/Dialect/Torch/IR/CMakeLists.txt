add_npcomp_dialect_library(NPCOMPTorchDialect
  TorchDialect.cpp
  TorchOps.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/npcomp/Dialect/Torch

  DEPENDS
  MLIRTorchOpsIncGen
  MLIRTorchOpInterfacesIncGen
  MLIRTorchTypesIncGen

  LINK_COMPONENTS
  Core

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSupport
  MLIRControlFlowInterfaces
  MLIRSideEffectInterfaces
  NPCOMPBasicpyDialect
  NPCOMPNumpyDialect
)
