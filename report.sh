# Included by mkws.sh - you can replace it with your own report-generation commands
cat $(find . -name "transcript" | sort) > transcripts.txt
TRANSCRIPT=transcripts.txt python hdl-tools/ersatz-gtest.py --gtest_output=xml:svunit.xml
