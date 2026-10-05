import socket,sys
proto,src,dst,port=sys.argv[1],sys.argv[2],sys.argv[3],int(sys.argv[4])
s=socket.socket(socket.AF_INET, socket.SOCK_STREAM if proto=='tcp' else socket.SOCK_DGRAM)
s.settimeout(2); s.bind((src,0))
try:
    s.connect((dst,port))
    if proto=='udp':
        s.send(b'x'); s.recv(10)
    print('PASA')
except (ConnectionRefusedError,):
    print('PASA')          # llegó al destino (puerto cerrado)
except (socket.timeout,TimeoutError):
    print('BLOQ')
except OSError as e:
    print('ERR:'+str(e))
