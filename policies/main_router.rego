package router

import data.finops_admission

default result := {}

result := data.finops_admission.main if {
  print("Evaluating request for ", input.request.object.metadata.name, input.request.object.apiVersion, input.request.object.kind)
  input.request.object.apiVersion  == "composition.krateo.io/v1-0-0"
  input.request.object.kind        == "VmAzure"
}