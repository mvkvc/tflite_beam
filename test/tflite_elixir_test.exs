defmodule TFLiteElixir.Test do
  use ExUnit.Case

  def verify_loaded_model(model, input_data, expected_out, print_state)
      when is_binary(input_data) and is_binary(expected_out) and
             is_boolean(print_state) do
    # build interpreter
    %{"TFLITE_METADATA" => <<28>>, "min_runtime_version" => "1.5.0"} =
      TFLiteElixir.FlatBufferModel.read_all_metadata!(model)

    true = TFLiteElixir.FlatBufferModel.initialized!(model)
    "1.5.0" = TFLiteElixir.FlatBufferModel.get_minimum_runtime!(model)
    resolver = TFLiteElixir.Ops.Builtin.BuiltinResolver.new!()
    builder = TFLiteElixir.InterpreterBuilder.new!(model, resolver)
    interpreter = TFLiteElixir.Interpreter.new!()
    TFLiteElixir.InterpreterBuilder.set_num_threads!(builder, 2)
    :ok = TFLiteElixir.InterpreterBuilder.build!(builder, interpreter)
    TFLiteElixir.Interpreter.set_num_threads!(interpreter, 2)

    # verify
    [0] = TFLiteElixir.Interpreter.inputs!(interpreter)
    [171] = TFLiteElixir.Interpreter.outputs!(interpreter)

    "map/TensorArrayStack/TensorArrayGatherV3" =
      TFLiteElixir.Interpreter.get_input_name!(interpreter, 0)

    "prediction" = TFLiteElixir.Interpreter.get_output_name!(interpreter, 0)

    input_tensor =
      %TFLiteElixir.TFLiteTensor{
        name: "map/TensorArrayStack/TensorArrayGatherV3",
        index: 0,
        shape: [1, 224, 224, 3],
        shape_signature: [1, 224, 224, 3],
        type: {:u, 8},
        quantization_params: %TFLiteElixir.TFLiteQuantizationParams{
          scale: [0.0078125],
          zero_point: [128],
          quantized_dimension: 0
        },
        sparsity_params: %{}
      } = TFLiteElixir.Interpreter.tensor!(interpreter, 0)

    [1, 224, 224, 3] = TFLiteElixir.TFLiteTensor.dims!(input_tensor)
    {:u, 8} = TFLiteElixir.TFLiteTensor.type(input_tensor)
    output_tensor = TFLiteElixir.Interpreter.tensor!(interpreter, 171)
    [1, 965] = TFLiteElixir.TFLiteTensor.dims!(output_tensor)
    {:u, 8} = TFLiteElixir.TFLiteTensor.type!(output_tensor)

    # run forwarding
    :ok = TFLiteElixir.Interpreter.allocate_tensors!(interpreter)
    TFLiteElixir.Interpreter.input_tensor!(interpreter, 0, input_data)
    TFLiteElixir.Interpreter.invoke!(interpreter)
    output_data = TFLiteElixir.Interpreter.output_tensor!(interpreter, 0)
    true = expected_out == output_data

    if print_state, do: TFLiteElixir.print_interpreter_state(interpreter)
    :ok
  end

  test "mobilenet_v2_1.0_224_inat_bird_quant buildFromFile" do
    filename = Path.join([__DIR__, "test_data", "mobilenet_v2_1.0_224_inat_bird_quant.tflite"])
    input_data = Path.join([__DIR__, "test_data", "parrot.bin"]) |> File.read!()
    expected_out = Path.join([__DIR__, "test_data", "parrot-expected-out.bin"]) |> File.read!()
    model = TFLiteElixir.FlatBufferModel.build_from_file!(filename)
    :ok = verify_loaded_model(model, input_data, expected_out, true)
  end

  test "TFLite.Interpreter.new(model_path)" do
    model_path = Path.join([__DIR__, "test_data", "mobilenet_v2_1.0_224_inat_bird_quant.tflite"])
    _interpreter = TFLiteElixir.Interpreter.new!(model_path)

    {error_at_stage, {:error, reason}} = TFLiteElixir.Interpreter.new("/dev/null")
    assert :build_from_file == error_at_stage
    assert reason == "cannot load flat buffer model from file"
  end

  test "mobilenet_v2_1.0_224_inat_bird_quant buildFromBuffer" do
    filename = Path.join([__DIR__, "test_data", "mobilenet_v2_1.0_224_inat_bird_quant.tflite"])
    input_data = Path.join([__DIR__, "test_data", "parrot.bin"]) |> File.read!()
    expected_out = Path.join([__DIR__, "test_data", "parrot-expected-out.bin"]) |> File.read!()
    model = TFLiteElixir.FlatBufferModel.build_from_buffer!(File.read!(filename))
    :ok = verify_loaded_model(model, input_data, expected_out, false)
  end

  with {:module, TFLiteElixir.Coral} <- Code.ensure_compiled(TFLiteElixir.Coral) do
    test "Contains EdgeTpu Custom Op" do
      filename = Path.join([__DIR__, "test_data", "mobilenet_v2_1.0_224_inat_bird_quant.tflite"])
      model = TFLiteElixir.FlatBufferModel.build_from_buffer!(File.read!(filename))
      ret = TFLiteElixir.Coral.contains_edge_tpu_custom_op?(model)

      :ok =
        case ret do
          false ->
            :ok

          {:error,
           "Coral support is disabled when compiling this library. Please enable Coral support and recompile this library."} ->
            :ok

          other ->
            false
        end

      filename =
        Path.join([__DIR__, "test_data", "mobilenet_v2_1.0_224_inat_bird_quant_edgetpu.tflite"])

      model = TFLiteElixir.FlatBufferModel.build_from_buffer!(File.read!(filename))
      ret = TFLiteElixir.Coral.contains_edge_tpu_custom_op?(model)

      :ok =
        case ret do
          true ->
            :ok

          {:error,
           "Coral support is disabled when compiling this library. Please enable Coral support and recompile this library."} ->
            :ok

          other ->
            false
        end
    end
  end
end
