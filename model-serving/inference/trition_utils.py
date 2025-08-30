import tritonclient.grpc as grpcclient
from tritonclient.grpc import InferenceServerClient, InferenceServerException

def trition_infer_request(
    client: InferenceServerClient, model_name: str, inputs, data_type: str
):
    input_tensors = [
        grpcclient.InferInput(name, data.shape, data_type)
        for name, data in inputs.items()
    ]
    for tensor, (_, data) in zip(input_tensors, inputs.items()):
        tensor.set_data_from_numpy(data)

    result = client.infer(model_name=model_name, inputs=input_tensors)
    return result
