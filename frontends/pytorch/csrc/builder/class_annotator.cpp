//===- class_annotator.cpp ------------------------------------------------===//
//
// This file is licensed under a pytorch-style license
// See frontends/pytorch/LICENSE for license information.
//
//===----------------------------------------------------------------------===//

#include "class_annotator.h"

#include <stdexcept>

using namespace torch_mlir;

//===----------------------------------------------------------------------===//
// Utilities
//===----------------------------------------------------------------------===//

// Prefix every line of `s` with `linePrefix`.
static std::string indentString(const std::string &linePrefix,
                                const std::string &s) {
  std::stringstream is(s);
  std::stringstream os;
  std::string line;
  while (std::getline(is, line)) {
    os << linePrefix << line << "\n";
  }
  return os.str();
}

//===----------------------------------------------------------------------===//
// ClassAnnotation
//===----------------------------------------------------------------------===//

ClassAnnotation::ClassAnnotation(c10::ClassTypePtr classType)
: classType(classType) {
  attributeAnnotations.resize(classType->getAttributes().size());
  methodAnnotations.resize(classType->methods().size());
}

std::vector<AttributeAnnotation> &
ClassAnnotation::getAttributeAnnotations() {
  // Halfhearted attempt to ensure consistency if the class type has
  // been mutated.
  //
  // We can't easily guard against attributes being removed and
  // then other attributes being added, or types changed, etc. without
  // effectively mirroring the entire ClassType.
  assert(attributeAnnotations.size() == classType->getAttributes().size() &&
         "annotations out of sync. class has been mutated");

  return attributeAnnotations;
}

std::vector<MethodAnnotation> &
ClassAnnotation::getMethodAnnotations() {
  // Halfhearted attempt to ensure consistency if the class type has
  // been mutated.
  //
  // We can't easily guard against methods being removed, added, or changed.
  assert(methodAnnotations.size() == classType->methods().size() &&
         "annotations out of sync. class has been mutated");

  return methodAnnotations;
}

//===----------------------------------------------------------------------===//
// ClassAnnotator
//===----------------------------------------------------------------------===//

static void exportNoneRecurse(ClassAnnotator &classAnnotator,
                              c10::ClassType *classType) {
  ClassAnnotation &classAnnotation =
      classAnnotator.getOrCreateClassAnnotation(classType);
  for (auto &attributeAnnotation : classAnnotation.getAttributeAnnotations()) {
    attributeAnnotation.isExported = false;
  }
  for (auto &methodAnnotation : classAnnotation.getMethodAnnotations()) {
    methodAnnotation.isExported = false;
  }
  for (auto &classAttribute : classType->getAttributes()) {
    if (auto childClassType = classAttribute.getType()->cast<c10::ClassType>()) {
      exportNoneRecurse(classAnnotator, childClassType.get());
    }
  }
}

void ClassAnnotator::exportNone(c10::ClassType &rootClassType) {
  exportNoneRecurse(*this, &rootClassType);
} 

void ClassAnnotator::exportPath(std::vector<std::string> exportedPath,
                                c10::ClassType &rootClassType) {
  if (exportedPath.size() == 0) {
    throw std::invalid_argument(
        "Empty exported path. Can only export a property of a class.");
  }
  c10::ClassType *classType = &rootClassType;
  // Reverse so that pop_back gives us the initial atoms first.
  std::reverse(exportedPath.begin(), exportedPath.end());
  while (exportedPath.size() != 1) {
    // This will throw in case of missing attribute.
    c10::TypePtr childType = classType->getAttribute(exportedPath.back());
    c10::ClassTypePtr childClassType = childType->cast<c10::ClassType>();
    if (!childClassType) {
      std::stringstream ss;
      ss << "class '" << classType->name()->qualifiedName()
         << "' does not have a submodule in attribute '" << exportedPath.back()
         << "'";
      throw std::invalid_argument(ss.str());
    }
    exportedPath.pop_back();
    classType = childClassType.get();
  }

  if (!classType->findAttribute(exportedPath.back()) &&
      !classType->findMethod(exportedPath.back())) {
    std::stringstream ss;
    ss << "class '" << classType->name()->qualifiedName()
       << "' does not have a method or attribute called '"
       << exportedPath.back() << "'";
    throw std::invalid_argument(ss.str()); 
  }
  ClassAnnotation &classAnnotation = getOrCreateClassAnnotation(classType);
  std::vector<AttributeAnnotation> &attributeAnnotations =
      classAnnotation.getAttributeAnnotations();
  const std::vector<c10::ClassAttribute> &classAttributes =
      classType->getAttributes();
  for (int i = 0, e = classAttributes.size(); i != e; i++) {
    if (classAttributes[i].getName() == exportedPath.back()) {
      attributeAnnotations[i].isExported = true;
    }
  }

  std::vector<MethodAnnotation> &methodAnnotations =
      classAnnotation.getMethodAnnotations();
  const std::vector<torch::jit::Function *> &methods = classType->methods();
  for (int i = 0, e = methods.size(); i != e; i++) {
    if (methods[i]->name() == exportedPath.back()) {
      methodAnnotations[i].isExported = true;
    }
  }
}

const ClassAnnotationMap &ClassAnnotator::getAnnotationMap() {
  return classAnnotations;
}

ClassAnnotation &
ClassAnnotator::getOrCreateClassAnnotation(c10::ClassType *classType) {
  auto it = classAnnotations.find(classType);
  if (it == classAnnotations.end()) {
    auto newAnnotation = std::make_unique<ClassAnnotation>(
        classType->shared_from_this()->cast<c10::ClassType>());
    it = classAnnotations.insert({classType, std::move(newAnnotation)}).first;
  }
  return *it->second;
}

//===----------------------------------------------------------------------===//
// toString methods
//===----------------------------------------------------------------------===//

std::string AttributeAnnotation::toString(const std::string &name) {
  std::stringstream ss;
  ss << "AttributeAnnotation('" << name << "') {\n";
  ss << "  isExported = " << (isExported ? "true" : "false") << "\n";
  ss << "}\n";
  return ss.str();
}

std::string MethodAnnotation::toString(const std::string &name) {
  std::stringstream ss;
  ss << "MethodAnnotation('" << name << "') {\n";
  ss << "  isExported = " << (isExported ? "true" : "false") << "\n";
  ss << "}\n";
  return ss.str();
}

std::string ClassAnnotation::toString() {
  std::stringstream ss;
  ss << "ClassAnnotation('" << classType->name()->qualifiedName() << "') {\n";

  const std::vector<c10::ClassAttribute> &classAttributes =
      classType->getAttributes();
  for (int i = 0, e = classAttributes.size(); i != e; i++) {
    ss << indentString(
        "  ", attributeAnnotations[i].toString(classAttributes[i].getName()));
  }
  const std::vector<torch::jit::Function *> &methods = classType->methods();
  for (int i = 0, e = methods.size(); i != e; i++) {
    ss << indentString("  ", methodAnnotations[i].toString(methods[i]->name()));
  }
  ss << "}\n";
  return ss.str();
}

std::string ClassAnnotator::toString() {
  std::stringstream ss;
  ss << "ClassAnnotator {\n";
  for (auto &p : classAnnotations) {
      ss << indentString("  ", p.second->toString());
  }
  ss << "}\n";
  return ss.str();
}

void torch_mlir::initClassAnnotatorBindings(py::module &m) {
  py::class_<ClassAnnotator>(m, "ClassAnnotator")
      .def(py::init<>())
      .def("exportPath", &ClassAnnotator::exportPath)
      .def("exportNone", &ClassAnnotator::exportNone)
      .def("__repr__", &ClassAnnotator::toString);
}
