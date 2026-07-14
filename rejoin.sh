#!/bin/bash
# NEXUS OS - Reassemble nexus.iso from parts
echo "Reassembling nexus.iso..."
cat parts/nexus.part.* > nexus.iso
echo "Done! Size: $(ls -lh nexus.iso | awk '{print $5}')"
echo "Verify: file nexus.iso"
