#!/bin/bash

echo "#!/bin/bash" > 07_liftover.sh
./06.b_do_liftover.awk 05_type_build_file.txt >> 07_liftover.sh
chmod 755 07_liftover.sh
