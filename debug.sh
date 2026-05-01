if [ $1 == 1 ]; then
  cmake -B build -DCMAKE_BUILD_TYPE=Debug
  echo "DEBUG"
else
  cmake -B build
fi

cmake --build build &&
./build/Zaitan.app/Contents/MacOS/Zaitan
