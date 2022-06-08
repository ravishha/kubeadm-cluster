#!/bin/bash
sudo update-crypto-policies --set LEGACY
sudo mount -o remount,exec /tmp
sudo mount -o remount,exec /home