defmodule Exop.Validation do
  @moduledoc """
    Provides high-level functions for a contract validation.
    The main function is valid?/2
    Mostly invokes Exop.ValidationChecks module functions.
  """

  require Logger

  alias Exop.ValidationChecks

  @type validation_error :: {:error, :validation_failed, list}

  @spec function_present?(Module.t, String.t) :: boolean
  defp function_present?(module, function_name) do
    :functions
    |> module.__info__
    |> Keyword.has_key?(function_name)
  end

  @doc """
  Validate received params over a contract.

  ## Examples

    iex> Exop.Validation.valid?([%{name: :param, opts: [required: true]}], [param: "hello"])
    :ok
  """
  @spec valid?(list(Map.t), Keyword.t | Map.t) :: :ok | validation_error
  def valid?(contract, received_params) do
    validation_results = validate(contract, received_params, [])

    if Enum.all?(validation_results, &(&1 == true)) do
      :ok
    else
      error_results = validation_results |> Enum.reject(&(&1 == true))
      log_errors(error_results)
      {:error, :validation_failed, error_results}
    end
  end

  @spec log_errors(Keyword.t) :: :ok | {:error, any}
  defp log_errors(reasons) do
    unless Mix.env == :test, do: Logger.error("#{__MODULE__} errors: #{errors_message(reasons)}")
  end

  @spec errors_message(Keyword.t) :: String.t
  defp errors_message(_reasons, acc \\ "")
  defp errors_message([], acc), do: acc
  defp errors_message([reason | t], acc) do
    errors_message(t, acc <> "\n#{elem(reason, 1)}")
  end

  @doc """
  Validate received params over a contract. Accumulate validation results into a list.

  ## Examples

    iex> Exop.Validation.validate([%{name: :param, opts: [required: true, type: :string]}], [param: "hello"], [])
    [true, true]
  """
  @spec validate([Map.t], Map.t | Keyword.t, list) :: list
  def validate([], _received_params, result), do: result
  def validate([contract_item | contract_tail], received_params, result) do
    checks_result = for {check_name, check_params} <- Map.get(contract_item, :opts), into: [] do
      check_function_name = ("check_" <> Atom.to_string(check_name)) |> String.to_atom
      cond do
        function_present?(__MODULE__, check_function_name) ->
          apply(__MODULE__, check_function_name, [received_params,
                                                  Map.get(contract_item, :name),
                                                  check_params])
        function_present?(ValidationChecks, check_function_name) ->
          apply(ValidationChecks, check_function_name, [received_params,
                                                       Map.get(contract_item, :name),
                                                       check_params])
        true -> true
      end
    end

    validate(contract_tail, received_params, result ++ List.flatten(checks_result))
  end

  @doc """
  Checks inner item of the contract param (which is a Map itself) with their own checks.

  ## Examples

    iex> Exop.Validation.check_inner(%{param: 1}, :param, [type: :integer, required: true])
    true
  """
  @spec check_inner(Map.t, atom, Map.t | Keyword.t) :: list
  def check_inner(check_items, item_name, cheks) when is_map(cheks) do
     checked_param = ValidationChecks.get_check_item(check_items, item_name)

     inner_contract = for {inner_param_name, inner_param_checks} <- cheks, into: [] do
       %{ name: inner_param_name, opts:  inner_param_checks }
     end

     validate(inner_contract, checked_param, [])
  end

  def check_inner(_received_params, _contract_item_name, _check_params), do: true
end