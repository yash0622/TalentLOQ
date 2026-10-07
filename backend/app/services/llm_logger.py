import sys
import logging
from typing import Optional

logger = logging.getLogger("talentloq.llm")

_call_counter = 0

def reset_llm_counter() -> None:
    """Resets call counter at the start of a request flow."""
    global _call_counter
    _call_counter = 0

def log_llm_usage(
    provider: str,
    model: str,
    input_tokens: int,
    output_tokens: int,
    total_tokens: Optional[int] = None,
    call_index: Optional[int] = None,
    latency_ms: Optional[float] = None,
) -> None:
    """
    Logs terminal token usage in the exact format required:
    [LLM]
    Provider: <provider name>
    Model: <model name>
    Input Tokens: <input token count>
    Output Tokens: <output token count>
    Total Tokens: <total token count>
    """
    global _call_counter
    _call_counter += 1

    if call_index is not None:
        tag = f"[LLM {call_index}]"
    elif _call_counter > 1:
        tag = f"[LLM {_call_counter}]"
    else:
        tag = "[LLM]"

    tot = total_tokens if (total_tokens is not None and total_tokens > 0) else (input_tokens + output_tokens)

    # Standardize provider display name
    p_lower = provider.lower()
    if "gemini" in p_lower or "google" in p_lower:
        prov_display = "Google Gemini"
    elif "groq" in p_lower:
        prov_display = "Groq"
    elif "openrouter" in p_lower:
        prov_display = "OpenRouter"
    elif "mistral" in p_lower:
        prov_display = "Mistral AI"
    elif "huggingface" in p_lower or "hf" in p_lower:
        prov_display = "Hugging Face"
    else:
        prov_display = provider

    latency_str = f"Latency: {latency_ms:.0f}ms\n" if latency_ms is not None else ""

    terminal_block = (
        f"\n{tag}\n"
        f"Provider: {prov_display}\n"
        f"Model: {model}\n"
        f"Input Tokens: {input_tokens}\n"
        f"Output Tokens: {output_tokens}\n"
        f"Total Tokens: {tot}\n"
        f"{latency_str}"
    )

    sys.stdout.write(terminal_block)
    sys.stdout.flush()

    logger.info(
        "%s Provider: %s | Model: %s | Input: %d | Output: %d | Total: %d%s",
        tag, prov_display, model, input_tokens, output_tokens, tot,
        f" | Latency: {latency_ms:.0f}ms" if latency_ms is not None else ""
    )
