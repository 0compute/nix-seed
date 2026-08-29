"""Hello world importing every dependency declared in pyproject.toml."""

import jax
import numpy
import pandas
import torch


def main() -> None:
    print("hello world")
    print(f"jax    {jax.__version__}")
    print(f"numpy  {numpy.__version__}")
    print(f"pandas {pandas.__version__}")
    print(f"torch  {torch.__version__}")


if __name__ == "__main__":
    main()
