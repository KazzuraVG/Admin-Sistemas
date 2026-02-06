echo Bienvenido
echo " "
hostname

echo " "
echo "IP Actual: "
ip addr show eth1 | grep inet

echo " "
echo "Espacio Disco Duro: "
df -h /