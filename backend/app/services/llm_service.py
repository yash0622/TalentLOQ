import os
import time
import asyncio
import logging
from typing import Optional, Dict, Any, List
from dotenv import load_dotenv
from app.services.llm_logger import log_llm_usage

load_dotenv()

logger = logging.getLogger("talentloq.llm")

FREE_GROQ_MODELS = ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b"]
FREE_GEMINI_MODELS = ["gemini-3.8-flash", "gemini-2.5-flash", "gemini-2.5-flash-lite"]
FREE_MISTRAL_MODELS = ["open-mistral-7b", "mistral-small-latest"]
FREE_OPENROUTER_MODELS = [
    "liquid/lfm-2.5-2.6b:free",
    "nvidia/nemotron-3.5-lightning:free",
]
FREE_HUGGINGFACE_MODELS = [
    "meta-llama/Llama-3.2-3B-Instruct",
    "meta-llama/Llama-3.1-8B-Instruct",
    "Qwen/Qwen2.5-7B-Instruct",
    "mistralai/Mistral-7B-Instruct-v0.3",
    "google/gemma-2-2b-it",
]

class LLMService:
    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(LLMService, cls).__new__(cls)
            cls._instance._init_clients()
        return cls._instance

    def _init_clients(self):
        self.groq_key = os.environ.get("GROQ_API_KEY", "").strip()
        self.openrouter_key = os.environ.get("OPENROUTER_API_KEY", "").strip()
        self.gemini_key = os.environ.get("GEMINI_API_KEY", os.environ.get("GOOGLE_API_KEY", "")).strip()
        self.mistral_key = os.environ.get("MISTRAL_API_KEY", "").strip()
        self.hf_key = os.environ.get("HUGGINGFACE_API_KEY", "").strip()

        # 1. Groq (Free Tier)
        self.groq_client = None
        if self.groq_key and not self.groq_key.startswith("your_"):
            try:
                from openai import OpenAI
                self.groq_client = OpenAI(base_url="https://api.groq.com/openai/v1", api_key=self.groq_key)
                logger.info("Groq free-tier client initialized.")
            except Exception as e:
                logger.warning(f"Could not initialize Groq client: {e}")

        # 2. OpenRouter (Free Tier :free models)
        self.openrouter_client = None
        if self.openrouter_key and not self.openrouter_key.startswith("your_"):
            try:
                from openai import OpenAI
                self.openrouter_client = OpenAI(base_url="https://openrouter.ai/api/v1", api_key=self.openrouter_key)
                logger.info("OpenRouter free-tier client initialized.")
            except Exception as e:
                logger.warning(f"Could not initialize OpenRouter client: {e}")

        # 3. Mistral (Free Tier)
        self.mistral_client = None
        if self.mistral_key and not self.mistral_key.startswith("your_"):
            try:
                from mistralai import Mistral
                self.mistral_client = Mistral(api_key=self.mistral_key)
                logger.info("Mistral free client initialized.")
            except Exception as e:
                logger.warning(f"Could not initialize Mistral client: {e}")

        # 4. Gemini (Google AI Studio Free Tier)
        self.gemini_client = None
        if self.gemini_key and not self.gemini_key.startswith("your_"):
            try:
                from google import genai
                self.gemini_client = genai.Client(api_key=self.gemini_key)
                logger.info("Gemini free client initialized.")
            except Exception as e:
                logger.warning(f"Could not initialize Gemini client: {e}")

        # 5. Hugging Face (Serverless Free Inference)
        self.hf_client = None
        if self.hf_key and not self.hf_key.startswith("your_"):
            try:
                from huggingface_hub import InferenceClient
                self.hf_client = InferenceClient(api_key=self.hf_key)
                logger.info("Hugging Face free serverless client initialized.")
            except Exception as e:
                logger.warning(f"Could not initialize Hugging Face client: {e}")

    @staticmethod
    def _print_token_usage(
        provider: str,
        model: str,
        prompt_tokens: int,
        completion_tokens: int,
        total_tokens: int,
        latency_ms: Optional[float] = None,
    ) -> Dict[str, int]:
        log_llm_usage(
            provider=provider,
            model=model,
            input_tokens=prompt_tokens,
            output_tokens=completion_tokens,
            total_tokens=total_tokens,
            latency_ms=latency_ms,
        )
        return {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": total_tokens,
        }

    async def generate(
        self,
        prompt: str,
        system_prompt: Optional[str] = None,
        max_tokens: int = 500,
        messages: Optional[List[Dict[str, str]]] = None,
    ) -> Dict[str, Any]:
        """
        Executes generation strictly through free models across available providers.
        Priority: Groq (Free) -> OpenRouter (:free) -> Mistral (Free) -> Gemini (Free) -> Hugging Face.
        Supports multi-turn chat messages when provided.
        """
        errors = []
        start_time = time.perf_counter()

        def _get_messages() -> List[Dict[str, str]]:
            if messages:
                return list(messages)
            msgs = []
            if system_prompt:
                msgs.append({"role": "system", "content": system_prompt})
            msgs.append({"role": "user", "content": prompt})
            return msgs

        # 1. Try Groq Free Tier
        if self.groq_client:
            for model_name in FREE_GROQ_MODELS:
                try:
                    chat_msgs = _get_messages()
                    # Ponytail: offload blocking sync SDK call to worker thread
                    res = await asyncio.to_thread(
                        self.groq_client.chat.completions.create,
                        model=model_name,
                        messages=chat_msgs,
                        max_tokens=max_tokens,
                    )
                    text = (res.choices[0].message.content or "").strip()
                    usage = getattr(res, "usage", None)
                    p_tok = int(getattr(usage, "prompt_tokens", 0) or 0)
                    c_tok = int(getattr(usage, "completion_tokens", 0) or 0)
                    t_tok = int(getattr(usage, "total_tokens", 0) or (p_tok + c_tok))
                    latency_ms = (time.perf_counter() - start_time) * 1000
                    tokens_dict = self._print_token_usage("groq", model_name, p_tok, c_tok, t_tok, latency_ms=latency_ms)

                    return {
                        "text": text,
                        "provider": "groq",
                        "model": model_name,
                        "is_free": True,
                        "fallback_used": False,
                        "tokens_used": tokens_dict,
                        "latency_ms": latency_ms,
                    }
                except Exception as e:
                    logger.warning(f"Groq {model_name} failed: {e}")
                    errors.append(f"Groq ({model_name}): {e}")

        # 2. Try Gemini Free Tier
        if self.gemini_client:
            for model_name in FREE_GEMINI_MODELS:
                try:
                    if messages:
                        full_content = "\n\n".join(
                            f"{m.get('role', 'user').capitalize()}: {m.get('content', '')}"
                            for m in messages
                        )
                    else:
                        full_content = f"{system_prompt}\n\n{prompt}" if system_prompt else prompt
                    # Ponytail: offload blocking sync SDK call to worker thread
                    res = await asyncio.to_thread(
                        self.gemini_client.models.generate_content,
                        model=model_name,
                        contents=full_content,
                    )
                    text = (res.text or "").strip()
                    usage = getattr(res, "usage_metadata", None)
                    p_tok = int(getattr(usage, "prompt_token_count", 0) or 0)
                    c_tok = int(getattr(usage, "candidates_token_count", 0) or 0)
                    t_tok = int(getattr(usage, "total_token_count", 0) or (p_tok + c_tok))
                    latency_ms = (time.perf_counter() - start_time) * 1000
                    tokens_dict = self._print_token_usage("gemini", model_name, p_tok, c_tok, t_tok, latency_ms=latency_ms)

                    return {
                        "text": text,
                        "provider": "gemini",
                        "model": model_name,
                        "is_free": True,
                        "fallback_used": True,
                        "tokens_used": tokens_dict,
                        "latency_ms": latency_ms,
                    }
                except Exception as e:
                    logger.warning(f"Gemini {model_name} failed: {e}")
                    errors.append(f"Gemini ({model_name}): {e}")

        # 3. Try Mistral Free
        if self.mistral_client:
            for model_name in FREE_MISTRAL_MODELS:
                try:
                    chat_msgs = _get_messages()
                    # Ponytail: offload blocking sync SDK call to worker thread
                    res = await asyncio.to_thread(
                        self.mistral_client.chat.complete,
                        model=model_name,
                        messages=chat_msgs,
                        max_tokens=max_tokens,
                    )
                    text = (res.choices[0].message.content or "").strip()
                    usage = getattr(res, "usage", None)
                    p_tok = int(getattr(usage, "prompt_tokens", 0) or 0)
                    c_tok = int(getattr(usage, "completion_tokens", 0) or 0)
                    t_tok = int(getattr(usage, "total_tokens", 0) or (p_tok + c_tok))
                    latency_ms = (time.perf_counter() - start_time) * 1000
                    tokens_dict = self._print_token_usage("mistral", model_name, p_tok, c_tok, t_tok, latency_ms=latency_ms)

                    return {
                        "text": text,
                        "provider": "mistral",
                        "model": model_name,
                        "is_free": True,
                        "fallback_used": True,
                        "tokens_used": tokens_dict,
                        "latency_ms": latency_ms,
                    }
                except Exception as e:
                    logger.warning(f"Mistral {model_name} failed: {e}")
                    errors.append(f"Mistral ({model_name}): {e}")

        # 4. Try OpenRouter :free Models
        if self.openrouter_client:
            for model_name in FREE_OPENROUTER_MODELS:
                try:
                    chat_msgs = _get_messages()
                    # Ponytail: offload blocking sync SDK call to worker thread
                    res = await asyncio.to_thread(
                        self.openrouter_client.chat.completions.create,
                        model=model_name,
                        messages=chat_msgs,
                        max_tokens=max_tokens,
                    )
                    text = (res.choices[0].message.content or "").strip()
                    usage = getattr(res, "usage", None)
                    p_tok = int(getattr(usage, "prompt_tokens", 0) or 0)
                    c_tok = int(getattr(usage, "completion_tokens", 0) or 0)
                    t_tok = int(getattr(usage, "total_tokens", 0) or (p_tok + c_tok))
                    latency_ms = (time.perf_counter() - start_time) * 1000
                    tokens_dict = self._print_token_usage("openrouter", model_name, p_tok, c_tok, t_tok, latency_ms=latency_ms)

                    return {
                        "text": text,
                        "provider": "openrouter",
                        "model": model_name,
                        "is_free": True,
                        "fallback_used": True,
                        "tokens_used": tokens_dict,
                        "latency_ms": latency_ms,
                    }
                except Exception as e:
                    logger.warning(f"OpenRouter {model_name} failed: {e}")
                    errors.append(f"OpenRouter ({model_name}): {e}")

        # 5. Try Hugging Face Free Serverless Models
        if self.hf_client:
            for model_name in FREE_HUGGINGFACE_MODELS:
                try:
                    chat_msgs = _get_messages()
                    res = await asyncio.to_thread(
                        self.hf_client.chat.completions.create,
                        model=model_name,
                        messages=chat_msgs,
                        max_tokens=max_tokens,
                    )
                    text = (res.choices[0].message.content or "").strip()
                    usage = getattr(res, "usage", None)
                    p_tok = int(getattr(usage, "prompt_tokens", 0) or 0)
                    c_tok = int(getattr(usage, "completion_tokens", 0) or 0)
                    t_tok = int(getattr(usage, "total_tokens", 0) or (p_tok + c_tok))
                    latency_ms = (time.perf_counter() - start_time) * 1000
                    tokens_dict = self._print_token_usage("huggingface", model_name, p_tok, c_tok, t_tok, latency_ms=latency_ms)

                    return {
                        "text": text,
                        "provider": "huggingface",
                        "model": model_name,
                        "is_free": True,
                        "fallback_used": True,
                        "tokens_used": tokens_dict,
                        "latency_ms": latency_ms,
                    }
                except Exception as e:
                    logger.warning(f"Hugging Face {model_name} failed: {e}")
                    errors.append(f"Hugging Face ({model_name}): {e}")

        return {
            "text": "All free AI models are currently unavailable.",
            "provider": "none",
            "model": "none",
            "is_free": True,
            "fallback_used": True,
            "errors": errors,
        }

    async def generate_stream(
        self,
        prompt: str,
        system_prompt: Optional[str] = None,
        max_tokens: int = 500,
        messages: Optional[List[Dict[str, str]]] = None,
    ):
        """
        Streams response tokens chunk-by-chunk using Groq, falling back to full generation.
        """
        def _get_messages() -> List[Dict[str, str]]:
            if messages:
                return list(messages)
            msgs = []
            if system_prompt:
                msgs.append({"role": "system", "content": system_prompt})
            msgs.append({"role": "user", "content": prompt})
            return msgs

        if self.groq_client:
            for model_name in FREE_GROQ_MODELS:
                try:
                    chat_msgs = _get_messages()
                    # Ponytail: sync stream offloaded cleanly
                    stream = await asyncio.to_thread(
                        self.groq_client.chat.completions.create,
                        model=model_name,
                        messages=chat_msgs,
                        max_tokens=max_tokens,
                        stream=True,
                    )
                    for chunk in stream:
                        delta = chunk.choices[0].delta.content if (chunk.choices and chunk.choices[0].delta) else ""
                        if delta:
                            yield delta
                    return
                except Exception as e:
                    logger.warning(f"Groq stream {model_name} failed: {e}")

        # Fallback to standard generation and yield in one or word pieces
        res = await self.generate(prompt=prompt, system_prompt=system_prompt, max_tokens=max_tokens, messages=messages)
        full_text = res.get("text", "")
        if full_text:
            yield full_text


llm_service = LLMService()