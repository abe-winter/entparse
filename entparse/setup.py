import setuptools, os

def load_requirements(fname):
  lines = list(open(fname))
  stripped = [line.strip() for line in lines]
  return filter(
    lambda line: line and not line.startswith('#'),
    lines
  )

REQS = parse_reqs(os.path.join(os.path.dirname(__file__), 'requirements.txt'))

ARGS = dict(
  name='entparse',
  version='0.0.0',
  description='',
  author='Abe Winter ',
  url='https://github.com/abe-winter/entparse',
  license='MIT',
  packages=setuptools.find_packages('.'),
  install_requires=REQS,
)

if __name__ == '__main__':
  setuptools.setup(**ARGS)
