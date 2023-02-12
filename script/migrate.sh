#bin/bash

cd misskeyV13
git reset master --hard
cd ../
cp -r misskeyV13/packages/frontend migrateWork
prettier -w migrateWork
prettier -w src


