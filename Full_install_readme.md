# 1) lancer l’install (Debian/Ubuntu/Kali)
bash ~/Downloads/install_can_tp.sh

# 2) démarrer le TP (ICSim + controls + CAN Explorer)
~/can-tp/start_can_lab.sh

# 3) (optionnel) démo d’accélération fluide en continu
~/can-tp/accelerate_loop.sh         # vcan0 + 100 ms/step
# ou plus lent / plus rapide :
~/can-tp/accelerate_loop.sh vcan0 0.2
~/can-tp/accelerate_loop.sh vcan0 0.05
