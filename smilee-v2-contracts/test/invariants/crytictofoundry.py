import re
import sys

folder = "ig"
if len(sys.argv):
    folder = sys.argv[1]


def outputToSol():
    data = ""
    with open('example.txt', 'r') as file:
        data = file.read()
        data = data.replace("*wait* ", "")
        print(data)
        data = re.sub(r"([a-zA-z]+\(.*\)) (Time delay: .*\n)", r"\2    \1\n", data)
        print(data)
        data = re.sub(r"Time delay: (\d+) .*\n", r"vm.warp(block.timestamp + \1)\n", data)
        print(data)
        data = re.sub(r"\)", r");", data)
        print(data)
        data = re.sub(r"0x([a-fA-F0-9]+),", r"address(0x\1),", data)
        print(data)
        data = re.sub(r"    ", r"        ", data)
        print(data)
    return data


def fillFile(content, folder="ig"):
    data = ""

    with open(f"{folder}/CryticToFoundry.t.sol", 'r') as file:
        data = file.read()
        ntest = data.count("function")
        data = re.sub(r"\}\n\}", r"}\n\n    function test_" + str(ntest) + r"() public {\n" + content + r"    }\n}", data)
    print(data)
    with open(f'{folder}/CryticToFoundry.t.sol', 'w') as file:
        file.write(data)


content = outputToSol()
print(content)
fillFile(content, folder)
