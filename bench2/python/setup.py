from setuptools import setup, Extension
from Cython.Build import cythonize

setup(ext_modules=cythonize([Extension("cy_bench", ["cy_bench.pyx"], extra_compile_args=["/O2", "/fp:precise"])]))
