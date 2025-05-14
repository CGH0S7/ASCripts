# ASCripts

在ASC中使用的功耗控制相关脚本

cpuctl.sh: 控制核心开启关闭

cpugovctl.sh: 控制核心工作频率

nvidiactl.sh: 控制显卡从pci总线弹出与恢复

nvidiasmictl.sh: 控制显卡工作状态，基于nvidia-smi命令

manual_parallel.py: 自动控制风扇状态，基于python的request库与服务器的ipmi功能

脚本由人工编写+人工智能完善实现，感谢`Claude 3.7 Sonnet`对脚本实现增强以及QLU的好朋友在赛场上赠予的风扇控制脚本

由于时间原因部分功能未完全进行验证，如nvidiactl.sh若出现问题可以采用手工方式弹卡（通过lspci | grep -i nvidia或nvidia-smi确定pci地址后解绑驱动再弹出echo -n "0000:ac:00.0" |  tee /sys/bus/pci/drivers/nvidia/unbind && echo -n 1 |  tee /sys/bus/pci/devices/0000\:ac\:00.0/remove），以及风扇控制也可以人工通过网页调度
