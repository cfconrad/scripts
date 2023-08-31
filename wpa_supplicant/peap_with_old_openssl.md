
# Test EAP-PEAP against very old tls version

```bash
netns=wifi_test_ns
radius_image=registry.opensuse.org/home/cfconrad/branches/opensuse/templates/images/tumbleweed/containers/openssl-0.9.8zg-freeradius-2.2.9
radius_container=freerad

for cmd in iw hostapd wpa_supplicant podman; do
  if ! command -v $cmd; then
    echo "ERROR: Missing $cmd"
    exit 2;
  fi
done

#setup
if ! ip netns list | grep $netns; then
  modprobe mac80211_hwsim radios=2;
  ip netns add $netns
  sleep 1
  iw phy phy0 set netns name $netns;
  ip netns exec $netns ip link set dev lo up
fi


if [ $(podman ps -f "name=$radius_container" --noheading | wc -l) -lt 1 ]; then
  podman run -dt --net ns:/var/run/netns/$netns --name "$radius_container" "$radius_image"
  podman cp "$radius_container":/etc/raddb $(pwd)/raddb
fi

if [ -e /var/run/hostapd.pid ]; then
  kill $(cat /var/run/hostapd.pid)
fi

cat > hostapd.conf <<-EOT
	ctrl_interface=/var/run/hostapd
	interface=wlan0
	driver=nl80211
	country_code=DE
	ssid=EAP_SSID
	hw_mode=g
	channel=1
	auth_algs=3
	wpa=2
	wpa_key_mgmt=WPA-EAP
	wpa_pairwise=CCMP
	rsn_pairwise=CCMP
	group_cipher=CCMP
	# Require IEEE 802.1X authorization
	ieee8021x=1
	eapol_version=2
	eap_message=ping-from-hostapd
	## RADIUS authentication server
	nas_identifier=the_ap
	auth_server_addr=127.0.0.1
	auth_server_port=1812
	auth_server_shared_secret=testing123
EOT

ip netns exec $netns ip addr add dev wlan0 10.4.4.1/24 
ip netns exec $netns hostapd -P /var/run/hostapd.pid -B hostapd.conf


cat > wpa_supplicant.conf << EOT
network={
    ssid="EAP_SSID"
    scan_ssid=1
    key_mgmt=WPA-EAP
    fragment_size=1300
    eap=PEAP
    identity="tester"
    anonymous_identity="anonymous"

    password="test1234"
    phase2="auth=MSCHAPV2"
    phase1="peaplabel=0"

    ca_cert="$(pwd)/raddb/certs/ca.pem"
}
EOT

# Creating a monitor device for debuggin
if [ ! -e /sys/class/net/mon1 ]; then
  iw phy phy1 interface add mon1 type monitor
fi

wpa_supplicant -c wpa_supplicant.conf -i wlan1 -ddd
```
