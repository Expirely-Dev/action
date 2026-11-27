// Command certserver serves TLS on 127.0.0.1 with certificates in known
// states, so the action's tests run without depending on a public host:
// port 8441 serves one valid for 200 days, 8442 one that expires in 10 days
// and 8443 one that expired 5 days ago. Each is signed by a fresh CA, written
// to the -ca path once every port listens, so a test can wait for that file
// and pass it to expirely --ca-file.
package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"flag"
	"fmt"
	"log"
	"math/big"
	"net"
	"os"
	"time"
)

type site struct {
	port     int
	notAfter time.Duration
}

func main() {
	caPath := flag.String("ca", "ca.pem", "where to write the CA certificate once every port listens")
	flag.Parse()

	now := time.Now()
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		log.Fatal(err)
	}
	caTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "expirely-action test CA"},
		NotBefore:             now.Add(-30 * 24 * time.Hour),
		NotAfter:              now.Add(365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageCertSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		log.Fatal(err)
	}
	ca, err := x509.ParseCertificate(caDER)
	if err != nil {
		log.Fatal(err)
	}

	sites := []site{
		{port: 8441, notAfter: 200 * 24 * time.Hour},
		{port: 8442, notAfter: 10 * 24 * time.Hour},
		{port: 8443, notAfter: -5 * 24 * time.Hour},
	}
	var listeners []net.Listener
	for i, s := range sites {
		key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if err != nil {
			log.Fatal(err)
		}
		template := &x509.Certificate{
			SerialNumber: big.NewInt(int64(i + 2)),
			Subject:      pkix.Name{CommonName: "localhost"},
			DNSNames:     []string{"localhost"},
			IPAddresses:  []net.IP{net.IPv4(127, 0, 0, 1)},
			NotBefore:    now.Add(-30 * 24 * time.Hour),
			NotAfter:     now.Add(s.notAfter),
			KeyUsage:     x509.KeyUsageDigitalSignature,
			ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		}
		der, err := x509.CreateCertificate(rand.Reader, template, ca, &key.PublicKey, caKey)
		if err != nil {
			log.Fatal(err)
		}
		cert := tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}
		l, err := tls.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", s.port), &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS12})
		if err != nil {
			log.Fatal(err)
		}
		listeners = append(listeners, l)
	}

	caPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caDER})
	if err := os.WriteFile(*caPath, caPEM, 0o600); err != nil {
		log.Fatal(err)
	}
	log.Printf("serving 127.0.0.1:8441 (valid), :8442 (expiring), :8443 (expired); CA at %s", *caPath)

	for _, l := range listeners[1:] {
		go serve(l)
	}
	serve(listeners[0])
}

func serve(l net.Listener) {
	for {
		conn, err := l.Accept()
		if err != nil {
			log.Fatal(err)
		}
		go func() {
			defer func() { _ = conn.Close() }()
			if tc, ok := conn.(*tls.Conn); ok {
				_ = tc.SetDeadline(time.Now().Add(10 * time.Second))
				_ = tc.Handshake()
			}
		}()
	}
}
