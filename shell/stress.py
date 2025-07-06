import multiprocessing
import time
import sys
import psutil # 引入新库

# --- 在这里配置你要消耗的资源百分比 ---

# 你想达到的 CPU 使用率目标百分比 (0-100)
# 例如，设置为 40，即代表目标为 40%
TARGET_CPU_PERCENTAGE = 40

# 你想消耗的内存量占总内存的百分比 (0-100)
# 例如，设置为 40，即代表目标为 40%
TARGET_MEMORY_PERCENTAGE = 50

# -------------------------------------------


# 定义一个按百分比“吃”CPU的函数
def cpu_eater_percentage(target_percent):
    """
    通过工作-睡眠循环，使单个CPU核心的使用率接近目标百分比。
    """
    print(f"✅  CPU 核心消耗进程已启动，目标使用率: {target_percent}%")
    try:
        # 我们将时间切片，比如每 0.1 秒为一个周期
        cycle_time = 0.1
        work_time = cycle_time * (target_percent / 100.0)
        sleep_time = cycle_time - work_time

        while True:
            # “工作”阶段：执行密集计算
            start_time = time.time()
            while time.time() - start_time < work_time:
                _ = 2**64

            # “睡眠”阶段：让出CPU
            time.sleep(sleep_time)

    except KeyboardInterrupt:
        pass

# 内存消耗函数保持不变，但我们会动态计算传入的 target_gb 参数
def memory_eater(target_gb):
    """
    一个消耗指定大小内存的函数。
    """
    print(f"✅  内存消耗进程已启动，目标：消耗 {target_gb:.2f} GB 内存...")
    memory_hog = []
    one_gb_in_bytes = 1024 * 1024 * 1024
    target_bytes = target_gb * one_gb_in_bytes

    chunk_size = 10 * 1024 * 1024  # 10MB
    chunk = ' ' * chunk_size

    consumed_bytes = 0

    try:
        while consumed_bytes < target_bytes:
            memory_hog.append(chunk)
            consumed_bytes += chunk_size

            if consumed_bytes % one_gb_in_bytes == 0:
                print(f"    RAM 已消耗: {consumed_bytes / one_gb_in_bytes} GB")

        print(f"✅  内存消耗已达到目标！当前已持有 {len(memory_hog) * chunk_size / one_gb_in_bytes:.2f} GB 内存。")
        print("   进程将保持运行以持有内存，按 Ctrl+C 停止所有进程。")
        while True:
            time.sleep(60)

    except MemoryError:
        print(f"❌  内存不足！无法分配更多内存。当前已持有 {len(memory_hog) * chunk_size / one_gb_in_bytes:.2f} GB 内存。")
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        pass


# 主程序入口
if __name__ == "__main__":
    # --- 自动检测系统资源 ---
    total_cpu_cores = psutil.cpu_count(logical=True)
    total_memory_info = psutil.virtual_memory()
    total_memory_gb = total_memory_info.total / (1024**3)

    print("====== 服务器资源压力测试脚本 (百分比模式) ======")
    print(f"系统信息: {total_cpu_cores} 个 CPU 核心, {total_memory_gb:.2f} GB 总内存")
    print(f"设定目标: CPU 使用率 ≈ {TARGET_CPU_PERCENTAGE}%, 内存使用率 ≈ {TARGET_MEMORY_PERCENTAGE}%")
    print("警告：这会显著影响服务器性能！")
    print("按 Ctrl+C 可以随时停止脚本。")
    print("--------------------------------------------------\n")

    processes = []

    # --- 启动 CPU 消耗进程 ---
    if TARGET_CPU_PERCENTAGE > 0:
        print(f"🚀 准备在 {total_cpu_cores} 个核心上启动 CPU 负载，目标使用率 {TARGET_CPU_PERCENTAGE}%...")
        # 在每个核心上都启动一个进程，以均匀地达到目标使用率
        for i in range(total_cpu_cores):
            p = multiprocessing.Process(target=cpu_eater_percentage, args=(TARGET_CPU_PERCENTAGE,))
            p.start()
            processes.append(p)

    # --- 启动内存消耗进程 ---
    if TARGET_MEMORY_PERCENTAGE > 0:
        # 计算目标内存消耗量
        memory_to_consume_gb = total_memory_gb * (TARGET_MEMORY_PERCENTAGE / 100.0)

        # 为了安全，我们检查一下是否超过总内存的95%，并给出警告
        if TARGET_MEMORY_PERCENTAGE > 95:
             print("🚨 警告：内存消耗目标超过95%，可能导致系统极度不稳定或崩溃！")

        print(f"\n🚀 开始启动内存消耗进程...")
        p = multiprocessing.Process(target=memory_eater, args=(memory_to_consume_gb,))
        p.start()
        processes.append(p)

    # 等待所有进程
    try:
        for p in processes:
            p.join()
    except KeyboardInterrupt:
        print("\n\n🛑 检测到 Ctrl+C，正在终止所有进程...")
        for p in processes:
            p.terminate()
            p.join()
        print("所有进程已停止。服务器资源即将释放。")
        sys.exit(0)