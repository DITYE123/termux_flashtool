#!/bin/bash
FULL_PACKAGE_IMG_DIR="/storage/emulated/0/images/"
SPECIFIC_FLASH_DIR="/storage/emulated/0/Download/"
MI_FLASH_BASE_DIR="/storage/emulated/0/mirom/miflash/"
MI_ROM_COMPRESSED_DIR="/storage/emulated/0/mirom/"

check_and_create_full_dir() {
    if [ ! -d "$FULL_PACKAGE_IMG_DIR" ]; then
        echo -e "\n\033[31m错误：刷机包目录不存在：$FULL_PACKAGE_IMG_DIR\033[0m"
        echo "请手动创建此目录并放置镜像文件。"
        return 1
    fi
    return 0
}

check_download_dir() {
    local DIR_PATH="$SPECIFIC_FLASH_DIR"
    if [ ! -d "$DIR_PATH" ]; then
        echo -e "\n\033[31m错误：自定义刷入目录不存在：$DIR_PATH\033[0m"
        echo "请手动创建此目录并放置镜像文件。"
        return 1
    fi
    return 0
}

check_mi_flash_dir() {
    local DIR_PATH="$MI_FLASH_BASE_DIR"
    if [ ! -d "$DIR_PATH" ]; then
        echo -e "\n\033[33m提示：小米线刷目录不存在，正在创建：$DIR_PATH\033[0m"
        mkdir -p "$DIR_PATH"
        if [ $? -ne 0 ]; then
            echo -e "\033[31m错误：目录创建失败，请检查文件系统权限。\033[0m"
            return 1
        fi
        echo -e "\033[32m目录创建成功。\033[0m"
    fi
    return 0
}

is_fastbootd() {
    local FASTBOOT_CHECK=$(sudo fastboot devices 2>/dev/null | grep 'fastboot')
    if [ -z "$FASTBOOT_CHECK" ]; then
        return 1
    fi

    local IS_USERSPACE=$(sudo fastboot getvar is-userspace 2>&1 | grep -i 'is-userspace' | sed 's/.*is-userspace: *\(.*\)/\1/i' | tr -d '\r\n[:space:]')
    
    if [[ "$IS_USERSPACE" =~ ^(true|yes)$ ]]; then
        return 0
    fi

    return 1
}

flash_with_retry() {
    local PARTITION="$1"
    local IMG_PATH="$2"
    local MAX_RETRIES=3
    local RETRY_COUNT=0
    local SUCCESS=0

    echo -e "\n开始刷入分区：$PARTITION"
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        
        if [ $RETRY_COUNT -gt 1 ]; then
            echo -e "\033[33m--- 尝试第 $RETRY_COUNT 次刷入... ---\033[0m"
        fi

        sudo fastboot flash "$PARTITION" "$IMG_PATH"
        
        if [ $? -eq 0 ]; then
            echo -e "\033[32m刷入成功。\033[0m"
            SUCCESS=1
            break
        else
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo -e "\033[31m刷入失败 (第 $RETRY_COUNT 次)。等待 1 秒后重试。\033[0m"
                sleep 1
            fi
        fi
    done

    if [ $SUCCESS -eq 0 ]; then
        echo -e "\n\033[41;37m!!! 致命错误: [$PARTITION] 分区刷入 $MAX_RETRIES 次后仍然失败，请检查镜像文件和设备连接!!!\033[0m"
        return 1
    fi
    return 0
}


free_cmd_line() {
    clear
    echo "==================== 命令行工具 ==================="
    echo "      请输入 fastboot 或 adb 命令。"
    echo "      输入 q 即可退出。"
    echo "======================================================================"
    
    while true; do
        echo -e "\n\033[33m请输入命令（q/quit退出）：\033[0m"
        read -p "> " CMD
        
        if [ "$CMD" = "q" ] || [ "$CMD" = "quit" ]; then
            echo -e "\n正在退出..."
            read -p "按 Enter 返回主菜单..."
            break
        fi
        
        if [ -z "$CMD" ]; then
            echo -e "\033[31m错误：命令不能为空。\033[0m"
            continue
        fi
        
        echo -e "\n执行命令：sudo $CMD"
        echo "--------------------------------------------------------"
        eval sudo "$CMD"
        echo "--------------------------------------------------------"
        echo -e "\033[32m命令执行完成。返回码：$?\033[0m"
    done
}

fix_fastbootd() {
    clear
    echo "==================== 修复 fastbootd 模式  ==================="
    echo "请将完整的镜像包解压到此目录：$FULL_PACKAGE_IMG_DIR"
    echo "强制要求刷入分区：boot、recovery"
    echo "存在即刷入分区：dtbo、init_boot、vendor_boot、modem"
    echo "=========================================================="
    
    read -p "确认执行修复操作吗？(y/n)：" CONFIRM_FIX
    if [ "$CONFIRM_FIX" != "y" ] && [ "$CONFIRM_FIX" != "Y" ]; then
        echo "操作已取消。"
        read -p "按 Enter 返回主菜单..."
        return
    fi
    
    check_and_create_full_dir
    if [ $? -ne 0 ]; then
        echo -e "\n目录准备失败。"
        read -p "按 Enter 返回主菜单..."
        return
    fi
    
    
    MANDATORY_PARTS=("boot" "recovery")
    ALL_CRITICAL_PARTS=("boot" "dtbo" "init_boot" "vendor_boot" "modem" "recovery")
    MISSING_MANDATORY=()
    
    
    for part in "${MANDATORY_PARTS[@]}"; do
        
        if [ ! -f "$FULL_PACKAGE_IMG_DIR/$part.img" ] && [ ! -f "$FULL_PACKAGE_IMG_DIR/$part.IMG" ]; then
            MISSING_MANDATORY+=("$part.img")
        fi
    done
    
    
    if [ ${#MISSING_MANDATORY[@]} -gt 0 ]; then
        echo -e "\n\033[31m缺少以下必须的镜像文件，操作终止：\033[0m"
        for missing in "${MISSING_MANDATORY[@]}"; do echo " - $missing"; done
        echo -e "\n请检查文件是否放置于 $FULL_PACKAGE_IMG_DIR 目录。"
        read -p "按 Enter 返回主菜单..."
        return
    fi
    
    
    PARTS_TO_FLASH=()
    echo -e "\n正在扫描可刷入的关键镜像文件..."
    for part in "${ALL_CRITICAL_PARTS[@]}"; do
        
        if [ -f "$FULL_PACKAGE_IMG_DIR/$part.img" ] || [ -f "$FULL_PACKAGE_IMG_DIR/$part.IMG" ]; then
            PARTS_TO_FLASH+=("$part")
            echo " - 找到并纳入刷入列表: $part"
        fi
    done

    if [ ${#PARTS_TO_FLASH[@]} -gt 0 ]; then
        echo -e "\n开始刷入分区（共 ${#PARTS_TO_FLASH[@]} 个已检测到的分区）..."
        for part in "${PARTS_TO_FLASH[@]}"; do
            
            local IMG_TO_FLASH="$FULL_PACKAGE_IMG_DIR/$part.img"
            if [ ! -f "$IMG_TO_FLASH" ]; then
                IMG_TO_FLASH="$FULL_PACKAGE_IMG_DIR/$part.IMG"
            fi
            
            flash_with_retry "$part" "$IMG_TO_FLASH"
            
            if [ $? -ne 0 ]; then
                 echo -e "\n\033[31m修复过程因 [$part] 刷入失败而中断！\033[0m"
                 read -p "按 Enter 返回主菜单..."
                 return
            fi
        done
    else
        
        echo -e "\n\033[31m在 $FULL_PACKAGE_IMG_DIR 目录下没有找到任何有效的关键分区镜像文件 (.img)！\033[0m"
        echo "请检查文件是否放置正确。"
        read -p "按 Enter 返回主菜单..."
        return
    fi
    
    
    echo -e "\n刷入完成，正在尝试重启到 fastbootd 模式..."
    sleep 2
    sudo fastboot reboot fastboot
    echo -e "\n重启命令已执行。"
    read -p "按 Enter 返回主菜单..."
}

unpack_mi_package() {
    clear
    echo "==================== 解压小米刷机包 (TGZ 格式) ==================="
    echo "扫描压缩包路径：$MI_ROM_COMPRESSED_DIR"
    echo "目标解压路径：$MI_FLASH_BASE_DIR"
    echo "=========================================================="
    
    check_mi_flash_dir
    if [ $? -ne 0 ]; then
        read -p "按 Enter 返回上一级菜单..."
        return 1
    fi
    
    pkg install tar gzip -y > /dev/null 2>&1

    TGZ_FILES=("$MI_ROM_COMPRESSED_DIR"/*.tgz)
    VALID_TGZ=()
    
    for tgz_path in "${TGZ_FILES[@]}"; do
        [ -f "$tgz_path" ] && VALID_TGZ+=("$tgz_path")
    done

    if [ ${#VALID_TGZ[@]} -eq 0 ]; then
        echo -e "\n\033[31m错误：在 $MI_ROM_COMPRESSED_DIR 路径下未找到 .tgz 格式的刷机包。\033[0m"
        echo "请将 .tgz 文件放置到指定目录。"
        read -p "按 Enter 返回上一级菜单..."
        return 1
    fi

    echo -e "\n请选择要解压的刷机包（输入序号）："
    select SELECTED_TGZ_PATH in "${VALID_TGZ[@]}" "取消操作"; do
        case "$SELECTED_TGZ_PATH" in
            "取消操作")
                echo "操作已取消。"
                read -p "按 Enter 返回上一级菜单..."
                return 1
                ;;
            "")
                echo "无效的选择，请重新输入。"
                continue
                ;;
            *)
                TGZ_NAME=$(basename "$SELECTED_TGZ_PATH")
                echo -e "\n已选择：\033[32m$TGZ_NAME\033[0m"
                read -p "确认要解压吗？(y/n)：" CONFIRM_UNPACK
                
                if [ "$CONFIRM_UNPACK" = "y" ] || [ "$CONFIRM_UNPACK" = "Y" ]; then
                    echo -e "\n==================== 开始解压 (过程可能较长) ===================="
                    sudo tar -xvf "$SELECTED_TGZ_PATH" -C "$MI_FLASH_BASE_DIR"
                    
                    if [ $? -eq 0 ]; then
                        echo -e "\n\033[32m刷机包解压成功。\033[0m"
                        read -p "按 Enter 自动进入刷机流程..."
                        return 0
                    else
                        echo -e "\n\033[31m解压失败，请检查文件完整性或目录权限。\033[0m"
                        read -p "按 Enter 返回上一级菜单..."
                        return 1
                    fi
                else
                    echo "操作已取消。"
                    read -p "按 Enter 返回上一级菜单..."
                    return 1
                fi
                ;;
        esac
    done
}

perform_mi_flash() {
    clear
    echo "==================== 选择小米刷机包并执行刷机脚本 ==================="
    echo "当前扫描目录：$MI_FLASH_BASE_DIR"
    echo "======================================================================"

    check_mi_flash_dir
    if [ $? -ne 0 ]; then
        read -p "按 Enter 返回主菜单..."
        return
    fi

    
    MI_ROM_DIRS=()
    for dir in "$MI_FLASH_BASE_DIR"*/; do
        if [ -d "$dir" ]; then
            if [ -f "${dir}flash_all.sh" ] || [ -f "${dir}flash_all_lock.sh" ]; then
                DIR_NAME=$(basename "$dir")
                MI_ROM_DIRS+=("$DIR_NAME")
            fi
        fi
    done

    if [ ${#MI_ROM_DIRS[@]} -eq 0 ]; then
        echo -e "\n\033[31m错误：未找到有效的小米刷机包文件夹。\033[0m"
        echo "请确保刷机包已解压至 $MI_FLASH_BASE_DIR 目录下，且包含 flash_all.sh 或 flash_all_lock.sh。"
        read -p "按 Enter 返回主菜单..."
        return
    fi

    echo -e "\n请选择要刷入的刷机包（输入序号）："
    select SELECTED_DIR_NAME in "${MI_ROM_DIRS[@]}" "取消操作"; do
        case "$SELECTED_DIR_NAME" in
            "取消操作")
                echo "操作已取消。"
                read -p "按 Enter 返回主菜单..."
                return
                ;;
            "")
                echo "无效的选择，请重新输入。"
                continue
                ;;
            *)
                ROM_PATH="$MI_FLASH_BASE_DIR$SELECTED_DIR_NAME"
                echo -e "\n已选择：\033[32m$SELECTED_DIR_NAME\033[0m"
                
                
                clear
                echo "==================== 小米线刷模式选择 ==================="
                echo "当前刷入包：\033[33m$SELECTED_DIR_NAME\033[0m"
                echo "1. 线刷并回锁 (执行 flash_all_lock.sh)"
                echo "2. 线刷不回锁 (执行 flash_all.sh)"
                echo "0. 返回上一级菜单"
                echo "===================================================="
                read -p "输入序号：" FLASH_CHOICE

                case "$FLASH_CHOICE" in
                    1)
                        SCRIPT_NAME="flash_all_lock.sh"
                        FLASH_MODE="线刷并回锁"
                        ;;
                    2)
                        SCRIPT_NAME="flash_all.sh"
                        FLASH_MODE="线刷不回锁"
                        ;;
                    0)
                        echo "返回刷机包选择界面..."
                        continue 2
                        ;;
                    *)
                        echo "无效的序号，返回主菜单。"
                        read -p "按 Enter 返回主菜单..."
                        return
                        ;;
                esac

                SCRIPT_PATH="$ROM_PATH/$SCRIPT_NAME"

                if [ ! -f "$SCRIPT_PATH" ]; then
                    echo -e "\n\033[31m错误：您选择的 [$FLASH_MODE] 对应的脚本 [$SCRIPT_NAME] 不存在！\033[0m"
                    read -p "按 Enter 返回主菜单..."
                    return
                fi

                echo -e "\n模式：\033[32m$FLASH_MODE\033[0m"
                echo "请确保设备已处于 Fastboot 模式。"
                read -p "确认执行脚本吗？(y/n)：" CONFIRM_EXEC
                
                if [ "$CONFIRM_EXEC" = "y" ] || [ "$CONFIRM_EXEC" = "Y" ]; then
                    echo -e "\n==================== 开始执行 $SCRIPT_NAME ===================="
                    
                    ( cd "$ROM_PATH" && sudo bash "$SCRIPT_PATH" )
                    
                    if [ $? -eq 0 ]; then
                        echo -e "\n\033[32m小米线刷脚本执行完成。\033[0m"
                    else
                        echo -e "\n\033[31m小米线刷脚本执行失败，请检查设备连接或脚本内容。\033[0m"
                    fi
                else
                    echo "操作已取消。"
                fi
                
                read -p "按 Enter 返回主菜单..."
                return
                ;;
        esac
    done
}

flash_mi_package() {
    while true; do
        clear
        echo "==================== 8. 小米线刷功能 (MiFlash) ==================="
        echo "请选择操作："
        echo "1. 选择已解压好的刷机包 ($MI_FLASH_BASE_DIR)"
        echo "2. 解压刷机包 (.tgz 文件位于 $MI_ROM_COMPRESSED_DIR)"
        echo "0. 返回主菜单"
        echo "============================================================="
        read -p "输入序号：" MI_CHOICE

        case "$MI_CHOICE" in
            1)
                perform_mi_flash
                return
                ;;
            2)
                
                if unpack_mi_package; then
                    perform_mi_flash
                    return
                fi
                
                ;;
            0)
                return
                ;;
            *)
                echo "无效的序号，请重新输入。"; 
                read -p "按 Enter 继续...";
                ;;
        esac
    done
}


flash_full_package() {
    clear
    echo "==================== 欧加系 fastbootd 全量包线刷  ==================="
    echo "镜像目录：$FULL_PACKAGE_IMG_DIR"
    echo "=========================================================="
    
    read -p "确认执行线刷操作吗？(y/n)：" CONFIRM_START
    if [ "$CONFIRM_START" != "y" ] && [ "$CONFIRM_START" != "Y" ]; then
        echo "操作已取消。"
        read -p "按 Enter 返回主菜单..."
        return
    fi
    
    check_and_create_full_dir
    if [ $? -ne 0 ]; then
        echo -e "\n目录准备失败。"
        read -p "按 Enter 返回主菜单..."
        return
    fi
    
    
    echo -e "\n==================== 启动模式自动检测与切换 ==================="
    
    REBOOT_SUCCESS=0
    
    
    echo "1. 尝试检测 Fastboot 设备连接..."
    local FASTBOOT_CHECK=$(sudo fastboot devices 2>/dev/null | grep 'fastboot')
    
    if [ ! -z "$FASTBOOT_CHECK" ]; then
        
        
        if is_fastbootd; then
            echo -e "=> \033[32m设备已处于 fastbootd 模式 (用户空间)！\033[0m"
            echo "3 秒后重新检查连接稳定性..."
            sleep 3
            
            FASTBOOT_RECHECK=$(sudo fastboot devices 2>/dev/null | grep 'fastboot')
            if [ ! -z "$FASTBOOT_RECHECK" ]; then
                 echo -e "=> \033[32mFastbootd 设备连接稳定，直接开始刷入！\033[0m"
                 REBOOT_SUCCESS=1
            else
                 echo -e "\n\033[31mFastbootd 设备连接不稳定，操作终止。\033[0m"
            fi
        
        else
            echo -e "=> \033[32mFastboot (Bootloader 模式) 已连接！\033[0m"
            
            
            echo -e "\n3 秒后重新检查连接稳定性..."
            sleep 3
            
            FASTBOOT_RECHECK=$(sudo fastboot devices 2>/dev/null | grep 'fastboot')
            
            if [ ! -z "$FASTBOOT_RECHECK" ]; then
                echo -e "=> \033[32mFastboot 设备连接正常。\033[0m"
                echo "准备重启到 fastbootd 模式... (若卡住，请使用主菜单的 **修复 fastbootd** 功能)"
                sudo fastboot reboot fastboot
                
                
                echo -e "\n等待设备进入 fastbootd 模式 (3秒延迟 + 状态检查)..."
                sleep 3 
                
                if is_fastbootd; then
                    echo -e "=> \033[32m设备成功进入 fastbootd 模式。\033[0m"
                    REBOOT_SUCCESS=1
                else
                    echo -e "\n\033[31m错误：重启后未检测到 fastbootd 设备！\033[0m"
                fi
                

            else
                echo -e "\n\033[31mFastboot 设备连接丢失或异常，操作终止。\033[0m"
            fi
        fi
        
    else
        echo "=> 未检测到 Fastboot 设备，尝试通过 ADB 启动..."

        
        echo -e "\n2. 尝试检测 ADB 设备连接..."
        sudo adb devices > /dev/null 2>&1
        
        ADB_CHECK=$(sudo adb devices 2>/dev/null | grep -v 'List of devices attached' | grep 'device')

        if [ ! -z "$ADB_CHECK" ]; then
            echo -e "=> ADB 设备已连接。"
            echo "提示：若设备上出现【允许此计算机调试】窗口，请务必选择【始终允许】！"
            
            
            echo -e "\n3 秒后重新检查连接稳定性..."
            sleep 3
            
            ADB_RECHECK=$(sudo adb devices 2>/dev/null | grep -v 'List of devices attached' | grep 'device')

            if [ ! -z "$ADB_RECHECK" ]; then
                echo -e "=> \033[32mADB 设备已授权并连接正常，正在执行重启命令。\033[0m"
                
                echo "正在使用 ADB 命令重启到 fastbootd 模式... (若卡住，请使用主菜单的 **修复 fastbootd** 功能)"
                sudo adb reboot fastboot
                
                
                echo -e "\n等待设备进入 fastbootd 模式 (3秒延迟 + 状态检查)..."
                sleep 3 
                
                if is_fastbootd; then
                    echo -e "=> \033[32m设备成功进入 fastbootd 模式。\033[0m"
                    REBOOT_SUCCESS=1
                else
                    echo -e "\n\033[31m错误：重启后未检测到 fastbootd 设备！\033[0m"
                fi
                

            else
                echo -e "\n\033[31mADB 授权失败或连接丢失，请检查 USB 连接及 ADB 授权设置。\033[0m"
            fi
        else
            
            echo -e "\n\033[31mFastboot 和 ADB 设备均未检测到。\033[0m"
            echo "请确认设备已进入 Fastboot 模式或已开启 ADB 调试并授权。"
        fi
    fi
    
    
    if [ $REBOOT_SUCCESS -eq 0 ]; then
        echo -e "\n启动 fastbootd 失败，操作终止！"
        read -p "按 Enter 返回主菜单..."
        return
    fi
    
    
    
    SPECIFIC_RECONSTRUCT_PARTS=("modem" "odm" "system" "system_dlkm" "system_ext" "vendor" "vendor_dlkm" "product")
    PARTITIONS_TO_RECONSTRUCT=()

    
    IMG_FILES=("$FULL_PACKAGE_IMG_DIR"/*.img "$FULL_PACKAGE_IMG_DIR"/*.IMG)
    VALID_IMGS=()
    
    for img_path in "${IMG_FILES[@]}"; do
        [ -f "$img_path" ] && VALID_IMGS+=("$img_path")
        PARTITION="${img_path##*/}" && PARTITION="${PARTITION%.*}"
        
        
        if [[ "$PARTITION" == my_* ]]; then
            [[ ! " ${PARTITIONS_TO_RECONSTRUCT[@]} " =~ " $PARTITION " ]] && PARTITIONS_TO_RECONSTRUCT+=("$PARTITION")
        fi
    done
    
    
    for part in "${SPECIFIC_RECONSTRUCT_PARTS[@]}"; do
        if [ -f "$FULL_PACKAGE_IMG_DIR/$part.img" ] || [ -f "$FULL_PACKAGE_IMG_DIR/$part.IMG" ]; then
             [[ ! " ${PARTITIONS_TO_RECONSTRUCT[@]} " =~ " $part " ]] && PARTITIONS_TO_RECONSTRUCT+=("$part")
        fi
    done
    
    if [ ${#VALID_IMGS[@]} -eq 0 ]; then
        echo -e "\n错误：在 $FULL_PACKAGE_IMG_DIR 目录下未找到有效的镜像文件。"
        read -p "按 Enter 返回主菜单..."
        return
    fi
    
    
    if [ ${#PARTITIONS_TO_RECONSTRUCT[@]} -gt 0 ]; then
        echo -e "\n开始重构逻辑分区（共 ${#PARTITIONS_TO_RECONSTRUCT[@]} 个）..."
        for part in "${PARTITIONS_TO_RECONSTRUCT[@]}"; do
            echo -e "\n重构：$part"
            
            sudo fastboot delete-logical-partition "${part}_a" 2>/dev/null
            sudo fastboot delete-logical-partition "${part}_b" 2>/dev/null
            sudo fastboot delete-logical-partition "${part}_a-cow" 2>/dev/null
            sudo fastboot delete-logical-partition "${part}_b-cow" 2>/dev/null
            sudo fastboot create-logical-partition "${part}_a" 1
            sudo fastboot create-logical-partition "${part}_b" 1
            echo "  - 重构完成。"
        done
    else
        echo -e "\n未检测到需要重构的动态分区，跳过重构步骤。"
    fi
    
    
    echo -e "\n开始刷入所有镜像文件（共 ${#VALID_IMGS[@]} 个）..."
    for img_path in "${VALID_IMGS[@]}"; do
        PARTITION="${img_path##*/}" && PARTITION="${PARTITION%.*}"
        
        flash_with_retry "$PARTITION" "$img_path"
        
        if [ $? -ne 0 ]; then
             echo -e "\n\033[31m线刷过程因 [$PARTITION] 刷入失败而中断！\033[0m"
             read -p "按 Enter 返回主菜单..."
             return
        fi
    done
    
    echo -e "\n所有镜像刷入完成。"
    
    
    read -p "是否执行恢复出厂设置（Data 分区将被清空）并重启？(y/n)：" FACTORY_RESET_AND_REBOOT
    
    if [ "$FACTORY_RESET_AND_REBOOT" = "y" ] || [ "$FACTORY_RESET_AND_REBOOT" = "Y" ]; then
        echo -e "\n执行恢复出厂设置 (fastboot erase userdata)..."
        sudo fastboot erase userdata
        
        echo -e "\n执行重启到系统 (fastboot reboot)..."
        sudo fastboot reboot
    else
        
        read -p "是否只重启到系统？(y/n)：" REBOOT_ONLY
        if [ "$REBOOT_ONLY" = "y" ] || [ "$REBOOT_ONLY" = "Y" ]; then
            echo -e "\n执行重启到系统 (fastboot reboot)..."
            sudo fastboot reboot
        else
            echo -e "\n保持在 Fastbootd 模式，返回主菜单。"
        fi
    fi
    
    read -p "按 Enter 返回主菜单..."
}

check_device_connection() {
    clear
    echo "==================== 检查设备连接状态 ==================="
    echo "正在检测 Fastboot 和 ADB 设备连接..."
    echo "=============================================================="
    
    
    local FASTBOOT_DEVICES=$(sudo fastboot devices 2>/dev/null | grep 'fastboot')
    
    local ADB_DEVICES=$(sudo adb devices 2>/dev/null | grep -v 'List of devices attached' | grep 'device')
    
    local FOUND_DEVICE=0
    
    echo -e "\n--- Fastboot 设备检测报告 ---"
    if [ -z "$FASTBOOT_DEVICES" ]; then
        echo "=> 未检测到 Fastboot 设备。"
    else
        FOUND_DEVICE=1
        
        
        local MODE_INFO=""
        if is_fastbootd; then
            MODE_INFO="\033[32mFastbootd 模式 (用户空间) 已连接。\033[0m"
        else
            MODE_INFO="\033[32mFastboot (Bootloader 模式) 已连接。\033[0m"
        fi
        
        echo -e "=> $MODE_INFO"
        
        
        echo "正在获取 Bootloader 锁状态..."
        
        
        local OEM_INFO_OUTPUT=$(sudo fastboot oem device-info 2>/dev/null)
        
        local UNLOCKED_STATUS="\033[33m未知 (无法获取信息)\033[0m"
        
        
        if echo "$OEM_INFO_OUTPUT" | grep -q 'Device unlocked: true'; then
            UNLOCKED_STATUS="\033[32m已解锁 (UNLOCKED)。\033[0m"
        elif echo "$OEM_INFO_OUTPUT" | grep -q 'Device unlocked: false'; then
            UNLOCKED_STATUS="\033[31m已锁定 (LOCKED)。\033[0m"
        fi
        
        echo -e "=> \033[36mBootloader 锁状态: $UNLOCKED_STATUS\033[0m"
        
        echo "------------------------"
        echo "$FASTBOOT_DEVICES"
        echo "------------------------"
    fi
    
    echo -e "\n--- ADB 设备检测报告 ---"
    if [ -z "$ADB_DEVICES" ]; then
        echo "=> 未检测到 ADB 设备。"
    else
        echo -e "=> \033[32mADB 设备已连接。\033[0m"
        echo "------------------------"
        echo "$ADB_DEVICES"
        echo "------------------------"
        FOUND_DEVICE=1
    fi
    
    if [ $FOUND_DEVICE -eq 0 ]; then
        echo -e "\n\033[31m总体报告：未检测到任何连接设备。\033[0m"
        echo "请检查 USB 连接、OTG 设置、驱动安装，以及设备是否进入 ADB/Fastboot 模式。"
    fi
    
    echo -e "\n检查完成。"
    read -p "按 Enter 返回主菜单..."
}

custom_flash_partition() {
    clear
    echo "==================== 2. 自定义刷入分区 (Fastboot Flash) ==================="
    echo "请将镜像文件 (.img/.IMG) 放置到此目录：$SPECIFIC_FLASH_DIR"
    echo "此功能仅执行 fastboot flash <分区名> <镜像路径>。"
    echo "===================================================="
    
    check_download_dir
    if [ $? -ne 0 ]; then
        echo -e "\n目录准备失败。"
        read -p "按 Enter 返回主菜单..."
        return
    fi
    
    
    IMG_FILES=("$SPECIFIC_FLASH_DIR"/*.img "$SPECIFIC_FLASH_DIR"/*.IMG)
    VALID_IMGS=()
    for img_path in "${IMG_FILES[@]}"; do
        [ -f "$img_path" ] && VALID_IMGS+=("$img_path")
    done
    
    if [ ${#VALID_IMGS[@]} -eq 0 ]; then
        echo -e "\n错误：在 $SPECIFIC_FLASH_DIR 目录下未找到任何镜像文件 (.img/.IMG)。"
        read -p "按 Enter 返回主菜单..."
        return
    fi
    
    
    IMG_NAMES=()
    for img_path in "${VALID_IMGS[@]}"; do
        IMG_NAMES+=("${img_path##*/}")
    done
    
    
    read -p "`echo -e '\n'`请输入目标分区名称（例如：boot）：" PARTITION
    [ -z "$PARTITION" ] && { echo "错误：分区名称不能为空。"; read -p "按 Enter 返回主菜单..."; return; }
    
    
    echo -e "\n请选择要刷入的镜像文件："
    select IMG_NAME in "${IMG_NAMES[@]}" "取消操作"; do
        case "$IMG_NAME" in
            "取消操作") 
                echo "操作已取消。"
                read -p "按 Enter 返回主菜单..."
                break 
                ;;
            "") 
                echo "无效的选择，请重新输入。"
                continue
                ;;
            *)
                SELECTED_IMG_PATH="$SPECIFIC_FLASH_DIR/$IMG_NAME"
                read -p "`echo -e '\n'`确认将 [$IMG_NAME] 刷入到 [$PARTITION] 分区吗？(y/n)：" CONFIRM_FLASH
                if [ "$CONFIRM_FLASH" != "y" ] && [ "$CONFIRM_FLASH" != "Y" ]; then
                    echo "操作已取消。"
                    read -p "按 Enter 返回主菜单..."
                    break
                fi
                
                
                flash_with_retry "$PARTITION" "$SELECTED_IMG_PATH"
                
                echo -e "\n操作完成。"
                read -p "按 Enter 返回主菜单..."
                break ;;
        esac
    done
}

show_main_menu() {
    clear
    echo "==================== Termux_flashtool v1.2bate@尘mc ==================="
    echo "1. 重启到指定模式"
    echo "2. 自定义刷入分区"
    echo "3. 欧加纯 fastbootd 线刷"
    echo "4. 检查设备连接与BL锁状态" 
    echo "5. 命令行"
    echo "6. 修复 fastbootd 功能"
    echo "7. 小米线刷功能" 
    echo "0. 退出工具箱"
    echo "==================================================================="
    read -p "输入功能序号 (0-8)：" CHOICE 
}

show_reboot_menu() {
    clear
    echo "==================== 重启模式选择 ==================="
    echo "1. 重启到系统  2. 重启到 bootloader  3. 重启到 fastbootd  4. 重启到 recovery"
    echo "0. 返回上一级菜单"
    echo "===================================================="
    read -p "输入序号：" REBOOT_CHOICE
}

while true; do
    show_main_menu
    case $CHOICE in
        1)
            while true; do
                show_reboot_menu
                
                if [ "$REBOOT_CHOICE" -ge 1 ] && [ "$REBOOT_CHOICE" -le 4 ]; then
                    
                    
                    case $REBOOT_CHOICE in
                        1) MODE="系统"; FASTBOOT_CMD="sudo fastboot reboot"; ADB_CMD="sudo adb reboot" ;;
                        2) MODE="bootloader"; FASTBOOT_CMD="sudo fastboot reboot bootloader"; ADB_CMD="sudo adb reboot bootloader" ;;
                        3) MODE="fastbootd"; FASTBOOT_CMD="sudo fastboot reboot fastboot"; ADB_CMD="sudo adb reboot fastboot" ;;
                        4) MODE="recovery"; FASTBOOT_CMD="sudo fastboot reboot recovery"; ADB_CMD="sudo adb reboot recovery" ;;
                    esac
                    
                    echo -e "\n目标：重启到 $MODE 模式。"
                    read -p "确认执行重启操作吗？(y/n)：" CONFIRM_REBOOT
                    if [ "$CONFIRM_REBOOT" != "y" ] && [ "$CONFIRM_REBOOT" != "Y" ]; then
                        echo "操作已取消。"
                        read -p "按 Enter 继续..."
                        continue
                    fi

                    
                    REBOOT_DONE=0
                    
                    
                    echo -e "\n--- 尝试 Fastboot 连接 ---"
                    FASTBOOT_CHECK=$(sudo fastboot devices 2>/dev/null | grep 'fastboot')
                    
                    if [ ! -z "$FASTBOOT_CHECK" ]; then
                        echo -e "=> \033[32mFastboot 设备已连接。\033[0m"
                        
                        
                        FASTBOOT_RECHECK=$(sudo fastboot devices 2>/dev/null | grep 'fastboot')
                        
                        if [ ! -z "$FASTBOOT_RECHECK" ]; then
                            echo -e "=> \033[32mFastboot 连接正常，正在执行重启命令。\033[0m"
                            echo "执行命令: $FASTBOOT_CMD"
                            $FASTBOOT_CMD
                            REBOOT_DONE=1
                        else
                            echo -e "\n\033[31mFastboot 设备连接不稳定，无法执行重启。\033[0m"
                        fi
                    fi
                    
                    
                    if [ $REBOOT_DONE -eq 0 ]; then
                        echo -e "\n--- 尝试 ADB 连接 ---"
                        
                        sudo adb devices > /dev/null 2>&1
                        
                        ADB_CHECK=$(sudo adb devices 2>/dev/null | grep -v 'List of devices attached' | grep 'device')

                        if [ ! -z "$ADB_CHECK" ]; then
                            echo -e "=> ADB 设备已连接。"
                            echo "提示：若设备上出现【允许此计算机调试】窗口，请务必选择【始终允许】！"
                            
                            
                            ADB_RECHECK=$(sudo adb devices 2>/dev/null | grep -v 'List of devices attached' | grep 'device')

                            if [ ! -z "$ADB_RECHECK" ]; then
                                echo -e "=> \033[32mADB 设备已授权并连接正常，正在执行重启命令。\033[0m"
                                echo "执行命令: $ADB_CMD"
                                $ADB_CMD
                                REBOOT_DONE=1
                            else
                                echo -e "\n\033[31mADB 授权失败或连接丢失，无法执行重启。\033[0m"
                            fi
                        else
                            echo "=> 未检测到 ADB 设备。"
                        fi
                    fi

                    
                    if [ $REBOOT_DONE -eq 1 ]; then
                        echo -e "\n\033[32m重启命令已发送。\033[0m"
                    else
                        echo -e "\n\033[31m设备连接失败或连接丢失，无法执行重启操作。\033[0m"
                    fi
                    
                    read -p "按 Enter 返回主菜单..."
                    break
                elif [ "$REBOOT_CHOICE" == "0" ]; then
                    break
                else
                    echo "无效的序号。"; 
                    read -p "按 Enter 继续..."; 
                    continue
                fi
            done
            ;;
        2) custom_flash_partition ;;
        3) flash_full_package ;;
        4) check_device_connection ;;
        5) free_cmd_line ;;
        6) fix_fastbootd ;;
        7) flash_mi_package ;; 
        0) echo "感谢使用，工具箱已退出。"; exit 0 ;;
        *) echo "无效的序号，请重新输入。"; read -p "按 Enter 继续..." ;;
    esac
done