import setuptools, os
from Cython.Build import cythonize

def load_requirements(fname):
  lines = list(open(fname))
  stripped = [line.strip() for line in lines]
  return filter(
    lambda line: line and not line.startswith('#'),
    lines
  )

REQS = load_requirements(os.path.join(os.path.dirname(__file__), 'requirements.txt'))

ARGS = dict(
  name='entparse',
  version='0.0.0',
  description='fast json entity parser for cython',
  author='Abe Winter ',
  url='https://github.com/abe-winter/entparse',
  license='MIT',
  ext_modules=cythonize('entparse.pyx', extra_compile_args=['-O3']),
  install_requires=REQS,
)

if __name__ == '__main__':
  setuptools.setup(**ARGS)
