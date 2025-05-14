import re
import requests
import warnings
import concurrent.futures
import sys
import multiprocessing

warnings.filterwarnings("ignore")


class Fans(object):
    headers = {
        "content-type": "application/json",
        "User-Agent": r"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36 Edg/117.0.2045.60",
    }

    def __init__(self, host, username, password):
        self.host = host
        self.username = username
        self.password = password

    def get_random(self):
        url = f"https://{self.host}/api/randomtag"
        res = requests.get(url, headers=self.headers, verify=False)
        return res.json()["random"]

    def get_session(self, random_string):
        url = f"https://{self.host}/api/session"
        self.headers["content-type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        data = {
            "encrypt_flag": 0,
            "username": self.username,
            "password": self.password,
            "login_tag": str(random_string)
        }
        response = requests.post(url, headers=self.headers, data=data, verify=False)
        token = re.findall("QSESSIONID=(.*?);", response.headers["Set-Cookie"])[0]
        self.headers["X-Csrftoken"] = response.json()["CSRFToken"]

        self.headers["Cookie"] = str("lang=zh-cn;QSESSIONID=" + token + "; refresh_disable=1")
        self.headers["content-type"] = "application/json"

    def get_fans(self):
        url = f"https://{self.host}/api/status/fan_info"
        response = requests.get(url, headers=self.headers, verify=False).json()
        for k, v in response.items():
            if k == "fans":
                for i in v:
                    print(i)

    def fans_mode(self, mode="manual"):
        url = f"https://{self.host}/api/settings/fans-mode"
        # manual - auto
        data = {"control_mode": mode}
        response = requests.put(url, headers=self.headers, json=data, verify=False)
        print("response:", response.text)

    def change_fans(self, rate=100, fans=12):
        def change_single_fan(fan_index):
            url = f'https://{self.host}/api/settings/fan/{fan_index}'
            data = {"duty": rate}
            response = requests.put(url=url, json=data, verify=False, headers=self.headers)
            response.encoding = "utf-8"
            print(f"The index {fan_index} fan change to {response.json()['duty']} %")
            return fan_index
            
        # Using ThreadPoolExecutor to change fans in parallel
        with concurrent.futures.ThreadPoolExecutor(max_workers=fans) as executor:
            futures = [executor.submit(change_single_fan, i) for i in range(fans)]
            for future in concurrent.futures.as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    print(f"An error occurred while changing fan: {e}")

def control_fan(host, username, password, rate=50, fans=12):
    """Function to control a single node's fans"""
    node_f = Fans(host=host, username=username, password=password)
    random_string = node_f.get_random()
    node_f.get_session(random_string)
    # node_f.get_fans()
    node_f.fans_mode(mode="manual")
    node_f.change_fans(rate=rate, fans=fans)
    print(f"Completed fan control for node {host}")

def control_fan_mode(host, username, password, mode="manual"):
    """Function to control a single node's fans mode"""
    node_f = Fans(host=host, username=username, password=password)
    random_string = node_f.get_random()
    node_f.get_session(random_string)
    # node_f.get_fans()
    node_f.fans_mode(mode=mode)
    print(f"Completed fan control for node {host} in {mode} mode")

def parse_node_range(node_spec):
    """
    Parse node specification string into a list of node numbers
    Formats supported:
    - Single node: "1"
    - Range of nodes: "1-5"
    """
    if "-" in node_spec:
        start, end = map(int, node_spec.split("-"))
        return list(range(start, end + 1))
    else:
        return [int(node_spec)]

def main():
    N1_bmc_host = "IP_ADDRESS"
    N2_bmc_host = "IP_ADDRESS"
    N3_bmc_host = "IP_ADDRESS"
    N4_bmc_host = "IP_ADDRESS"
    N5_bmc_host = "IP_ADDRESS"
    username = "admin"
    password = "admin"
    
    # Map node numbers to hosts
    node_hosts = {
        1: N1_bmc_host,
        2: N2_bmc_host,
        3: N3_bmc_host,
        4: N4_bmc_host,
        5: N5_bmc_host
    }
    
    # Default fan speed percentage
    rate = 20
    
    # Default to all nodes
    nodes_to_control = list(range(1, 6))
    
    # Parse command line arguments
    if len(sys.argv) < 2:
        print(f"Usage: python {sys.argv[0]} <node_spec> [rate]")
        print("Examples:")
        print(f"  python {sys.argv[0]} 1-5 30  # Set 30% fan speed on nodes 1-5")
        print(f"  python {sys.argv[0]} 1 20    # Set 20% fan speed on node 1")
        print(f"Using default: all nodes at {rate}% fan speed")
    else:
        # First argument is node specification
        try:
            nodes_to_control = parse_node_range(sys.argv[1])
            # Check if nodes are valid
            for node in nodes_to_control:
                if node < 1 or node > 5:
                    print(f"Warning: Node {node} is out of range (1-5). It will be skipped.")
            # Filter out invalid nodes
            nodes_to_control = [n for n in nodes_to_control if 1 <= n <= 5]
        except ValueError:
            print(f"Invalid node specification: {sys.argv[1]}. Using all nodes.")
        
        # Second argument is fan rate if provided
        if len(sys.argv) > 2:
            try:
                rate = int(sys.argv[2])
                if rate < 0 or rate > 100:
                    print(f"Warning: Fan rate should be between 0-100. Using provided value: {rate}%")
            except ValueError:
                print(f"Invalid rate parameter: {sys.argv[2]}. Using default rate: {rate}%")
    
    print(f"Setting fan rate to {rate}% for nodes: {nodes_to_control}")
    
    fans = 12  # Number of fans to control

    # Get the hosts for the specified nodes
    hosts_to_control = []
    for node_num in nodes_to_control:
        host = node_hosts.get(node_num)
        if host:
            hosts_to_control.append((host, username, password, rate, fans))
        else:
            print(f"Node {node_num} not found in configuration")
    
    # Control all specified nodes in parallel using multiprocessing
    # Create a process for each node
    processes = []
    for args in hosts_to_control:
        p = multiprocessing.Process(target=control_fan, args=args)
        processes.append(p)
        p.start()
    
    # Wait for all processes to complete
    for p in processes:
        p.join()
    
    print("All fan control operations completed!")

if __name__ == '__main__':
    main()
