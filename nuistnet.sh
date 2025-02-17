#!/bin/bash
# debug=1 # 开启debug

# 用户名 密码
username='username'
password='password'


# 网络供应商
isp="校园网"
# isp="中国移动"
# isp="中国电信"
# isp="中国联通"

retryLimit="3" # 当异常响应次数大于该数值时，将尝试强制登出并重新登陆
retryFile=".nuistnetRetry" # 历史文件

userAgent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/84.0.4147.105 Safari/537.36"
loginServer='10.255.255.34'
getIPUrl="http://${loginServer}/api/v1/ip"
loginUrl="http://${loginServer}/api/v1/login"
infoUrl="http://${loginServer}/api/v1/fresh"
logoutUrl="http://${loginServer}/api/v1/logout"


fontRed='\033[31m'
fontGreen='\033[32m'
fontBlue='\033[36m'
fontNormal='\033[0m'

function echoRed() {
    echo -e "${fontRed}${*}${fontNormal}"
}
function echoBlue() {
    echo -e "${fontBlue}${*}${fontNormal}"
}
function echoGreen() {
    echo -e "${fontGreen}${*}${fontNormal}"
}
function debug() {
    if [ "$debug" == "1" ]; then
        echo "$*" 
    fi
}

function ShowHelp() {
    echo "南信大校园网络自动脚本，适配新系统(登录地址为10.255.255.34)"
    echo "脚本依赖于bash环境以及curl工具"
    echoRed "使用前需要修改脚本开头的相关参数"
    echoRed "脚本可能由于用户环境不同而无法使用，本人不保证脚本的可用性以及对使用该脚本造成的任何后果负责"
    echoGreen "用法:\n${0}         检测网络 并尝试登陆\n${0} login   强制执行登陆\n${0} logout  强制注销\n${0} status  显示登陆信息\n${0} help    显示帮助"
    return 0
}

function GetIP() { # 从学校api获取本机IP地址 # 返回0 成功 返回1失败
    local curlInfo curlCode
    echoBlue '获取本地IP...' 1>&2
    curlInfo=$(curl --connect-timeout 5 -X "GET" -w "\nCode:%{response_code}" -H "User-Agent: ${userAgent}" "${getIPUrl}")
    curlCode="$?"
    debug "${curlInfo}" 1>&2
    if [[ "$curlCode" -ne 0 ]]; then
        echoRed "curl 错误 Code:${curlCode}" 1>&2
        return 1
    else
        local responseCode=$(echo "${curlInfo}" | sed -n '$p' | sed -e "s/.*Code://g")
        if [[ "$responseCode" != "200" ]]; then
            echoRed "Http响应码错误 Code:${responseCode}" 1>&2
            return 1
        else
            curlInfo=$(echo "${curlInfo}" | sed -e 's/Code:...//g' | tr -d '\r' | sed -e 's/^[[:blank:]]*//g' -e 's/[[:blank:]]*$//g' | tr -d '\n')
            local IP=$(echo "${curlInfo}"  | sed -n "s/.*\"data\":[[:blank:]]*\"\([0-9.]\+\)\".*/\1/p")
            local apiCode=$(echo "${curlInfo}" | sed -n "s/.*\"code\":[[:blank:]]*\([0-9]\+\).*/\1/p")
            if [[ "${apiCode}" != "200" ]]; then
                echoRed "api响应码错误 Code:${apiCode}" 1>&2
                return 1
            elif [[ -z "${IP}" ]]; then
                echoRed "api返回IP为空" 1>&2
                return 1
            fi
            echo "$IP"
            echoGreen "IP获取成功" 1>&2
            echoGreen "地址: ${IP}" 1>&2
            return 0
        fi
        
    fi
}
function GetChannelId() { # 从学校api获取ISP id # 返回0 成功 返回1失败
    local curlInfo curlCode
    if [[ -z "${IP}" ]]; then
        IP=$(GetIP)
        if [[ "$?" -ne "0" ]]; then
            echoRed 'IP获取失败' 1>&2
            exit 1
        fi
    fi
    local randomInfo="${RANDOM}"
    if [[ -z "$randomInfo" ]]; then
        randomInfo="username"
    fi
    local postBody="{\"username\":\"${randomInfo}\",\"password\":\"${randomInfo}\",\"channel\":\"_GET\",\"ifautologin\":\"0\",\"pagesign\":\"firstauth\",\"usripadd\":\"${IP}\"}"
    curlInfo=$(curl --connect-timeout 5 -X "POST" -w "\nCode:%{response_code}" -H "User-Agent: ${userAgent}" -d "${postBody}" "${loginUrl}" | iconv -f GB2312 -t UTF-8)
    curlCode="$?"
    debug "${curlInfo}" 1>&2
    if [[ "$curlCode" -ne 0 ]]; then
        echoRed "curl 错误 Code:${curlCode}" 1>&2
        return 1
    else
        local responseCode=$(echo "${curlInfo}" | sed -n '$p' | sed -e "s/.*Code://g")
        if [[ "$responseCode" != "200" ]]; then
            echoRed "Http响应码错误 Code:${responseCode}" 1>&2
            return 1
        else
            curlInfo=$(echo "${curlInfo}" | sed -e 's/Code:...//g' | tr -d '\r' | sed -e 's/^[[:blank:]]*//g' -e 's/[[:blank:]]*$//g' | tr -d '\n')
            local apiCode=$(echo "${curlInfo}" | sed -n "s/.*\"code\":[[:blank:]]*\([0-9]\+\).*/\1/p")
            local reauth=$(echo "${curlInfo}" | sed -n "s/.*\"reauth\":[[:blank:]]*\([[:alpha:]]\+\).*/\1/p")
            if [[ "${apiCode}" != "200" ]]; then
                echoRed "api响应码错误 Code:${apiCode}" 1>&2
                local message=$(echo "${curlInfo}" | sed -n "s/.*\"message\":[[:blank:]]*\"\([^\"]\+\)\".*/\1/p")
                echo "信息:${message}" 1>&2
                return 1
            elif [[ "${reauth}" != "true" ]]; then
                echoRed "reauth错误 reauth:${reauth}" 1>&2
                return 1
            else
                local channelInfo=$(echo "${curlInfo}" | sed -e "s/.*\"channels\"://g" -e "s/.*\[//g" -e "s/\].*//g" -e "s/},{/\n/g" | tr -d '{' | tr -d '}')
                local channelId=$(echo "${channelInfo}" | grep "${isp}" | sed -n '1p' | sed -n "s/.*\"id\":[[:blank:]]*\"\([[:digit:]]\+\)\".*/\1/p")
                if [[ -z "${channelId}" ]]; then
                    echoRed "无法获取指定channelId" 1>&2
                    return 1
                else
                    echo "${channelId}"
                    echoGreen "channelId获取成功" 1>&2
                    echoGreen "id: ${channelId}" 1>&2
                    return 0
                fi
            fi
        fi
    fi
}
function Login() { # 进行登录操作 返回0 成功 返回1失败
    local curlInfo curlCode
    if [[ -z "${IP}" ]]; then
        IP=$(GetIP)
        if [[ "$?" -ne "0" ]]; then
            echoRed 'IP获取失败' 1>&2
            exit 1
        fi
    fi
    echoBlue "尝试登录..." 1>&2
    local postBody="{\"username\":\"${username}\",\"password\":\"${password}\",\"channel\":\"${channelId}\",\"ifautologin\":\"0\",\"pagesign\":\"secondauth\",\"usripadd\":\"${IP}\"}"
    curlInfo=$(curl --connect-timeout 5 -X "POST" -w "\nCode:%{response_code}" -H "User-Agent: ${userAgent}" -d "${postBody}" "${loginUrl}" | iconv -f GB2312 -t UTF-8)
    curlCode="$?"
    debug "${curlInfo}" 1>&2
    if [[ "$curlCode" -ne 0 ]]; then
        echoRed "curl 错误 Code:${curlCode}" 1>&2
        return 1
    else
        local responseCode=$(echo "${curlInfo}" | sed -n '$p' | sed -e "s/.*Code://g")
        if [[ "$responseCode" != "200" ]]; then
            echoRed "Http响应码错误 Code:${responseCode}" 1>&2
            echo "在未设置用户名、密码的情况下可能出现此错误，建议检测脚本开头用户名密码设置。" 1>&2
            return 1
        else
            curlInfo=$(echo "${curlInfo}" | sed -e 's/Code:...//g' | tr -d '\r' | sed -e 's/^[[:blank:]]*//g' -e 's/[[:blank:]]*$//g' | tr -d '\n')
            local apiCode=$(echo "${curlInfo}" | sed -n "s/.*\"code\":[[:blank:]]*\([0-9]\+\).*/\1/p")
            if [[ "${apiCode}" != "200" ]]; then
                echoRed "api响应码错误 Code:${apiCode}" 1>&2
                local message=$(echo "${curlInfo}" | sed -n "s/.*\"message\":[[:blank:]]*\"\([^\"]\+\)\".*/\1/p")
                echoRed "message: ${message}" 1>&2
                if [ "${message}" == "Passwd_Err" ]; then
                    echo "翻译：密码错误" 1>&2
                fi
                if [ "${message}" == "UserName_Err" ]; then
                    echo "翻译：用户名错误" 1>&2
                fi
                return 1
            else
                echoGreen "登录成功!" 1>&2
                return 0
            fi
        fi
    fi
}
function GetInfo() { # 从学校api获取登陆信息 返回 0 查询成功 1 失败
    local curlInfo curlCode
    local randomInfo="${RANDOM}"
    if [[ -z "$randomInfo" ]]; then
        randomInfo="username"
    fi
    echoBlue "获取当前登录信息..." 1>&2
    if [[ -z "${IP}" ]]; then
        IP=$(GetIP)
        if [[ "$?" -ne "0" ]]; then
            echoRed 'IP获取失败' 1>&2
            exit 1
        fi
    fi

    local postBody="{\"username\":\"${randomInfo}\",\"password\":\"${randomInfo}\",\"channel\":\"_ONELINEINFO\",\"ifautologin\":\"0\",\"pagesign\":\"thirdauth\",\"usripadd\":\"${IP}\"}"
    curlInfo=$(curl --connect-timeout 5 -X "POST" -w "\nCode:%{response_code}" -H "User-Agent: ${userAgent}" -d "${postBody}" "${infoUrl}" | iconv -f GB2312 -t UTF-8)
    curlCode="$?"
    debug "${curlInfo}" 1>&2
    if [[ "$curlCode" -ne 0 ]]; then
        echoRed "curl 错误 Code:${curlCode}" 1>&2
        return 1
    else
        local responseCode=$(echo "${curlInfo}" | sed -n '$p' | sed -e "s/.*Code://g")
        if [[ "$responseCode" != "200" ]]; then
            echoRed "Http响应码错误 Code:${responseCode}" 1>&2
            return 1
        else
            curlInfo=$(echo "${curlInfo}" | sed -e 's/Code:...//g' | tr -d '\r' | sed -e 's/^[[:blank:]]*//g' -e 's/[[:blank:]]*$//g' | tr -d '\n')
            local apiCode=$(echo "${curlInfo}" | sed -n "s/.*\"code\":[[:blank:]]*\([0-9]\+\).*/\1/p")
            if [[ "${apiCode}" != "200" ]]; then
                echoRed "api响应码错误 Code:${apiCode}" 1>&2
                local message=$(echo "${curlInfo}" | sed -n "s/.*\"message\":[[:blank:]]*\"\([^\"]\+\)\".*/\1/p")
                echo "信息:${message}" 1>&2
                return 1
            else
                echoGreen "查询成功!" 1>&2
                local outport=$(echo "${curlInfo}" | sed -n "s/.*\"outport\":[[:blank:]]*\"\([^\"]\+\)\".*/\1/p")
                local duration=$(echo "${curlInfo}" | sed -n "s/.*\"duration\":[[:blank:]]*\"\([^\"]\+\)\".*/\1/p")
                echo "网络出口:${outport}"
                local hours=$((${duration}/3600))
                local minutes=$((${duration}%3600/60))
                local seconds=$((${duration}%60))
                echo "时长:${hours}小时${minutes}分钟${seconds}秒"
                if [[ "${outport}" == "初始出口" ]]; then
                    echo "翻译:未登录"
                fi
                if [[ "${outport}" == "0.00" ]]; then
                    echo "翻译:未登录"
                fi
                return 0
            fi
        fi
    fi
}
function Logout() { # 登出当前账户 返回 0 查询成功 1 失败
    local curlInfo curlCode
    local randomInfo="${RANDOM}"
    if [[ -z "$randomInfo" ]]; then
        randomInfo="username"
    fi
    echoBlue "尝试登出..." 1>&2

    if [[ -z "${IP}" ]]; then
        IP=$(GetIP)
        if [[ "$?" -ne "0" ]]; then
            echoRed 'IP获取失败' 1>&2
            exit 1
        fi
    fi

    local postBody="{\"username\":\"${randomInfo}\",\"password\":\"${randomInfo}\",\"ifautologin\":\"0\",\"pagesign\":\"thirdauth\",\"channel\":\"0\",\"usripadd\":\"${IP}\"}"
    curlInfo=$(curl --connect-timeout 5 -X "POST" -w "\nCode:%{response_code}" -H "User-Agent: ${userAgent}" -d "${postBody}" "${logoutUrl}" | iconv -f GB2312 -t UTF-8)
    curlCode="$?"
    debug "${curlInfo}" 1>&2
    if [[ "$curlCode" -ne 0 ]]; then
        echoRed "curl 错误 Code:${curlCode}" 1>&2
        return 1
    else
        local responseCode=$(echo "${curlInfo}" | sed -n '$p' | sed -e "s/.*Code://g")
        if [[ "$responseCode" != "200" ]]; then
            echoRed "Http响应码错误 Code:${responseCode}" 1>&2
            return 1
        else
            curlInfo=$(echo "${curlInfo}" | sed -e 's/Code:...//g' | tr -d '\r' | sed -e 's/^[[:blank:]]*//g' -e 's/[[:blank:]]*$//g' | tr -d '\n')
            local apiCode=$(echo "${curlInfo}" | sed -n "s/.*\"code\":[[:blank:]]*\([0-9]\+\).*/\1/p")
            local message=$(echo "${curlInfo}" | sed -n "s/.*\"message\":[[:blank:]]*\"\([^\"]\+\)\".*/\1/p")
            if [[ "${apiCode}" != "200" ]]; then
                echoRed "api响应码错误 Code:${apiCode}" 1>&2
                echo "信息:${message}" 1>&2
                return 1
            else
                echoGreen "退出成功!" 1>&2
                echo "信息:${message}" 1>&2
                return 0
            fi
        fi
    fi
}
function GetChannelIdOffline() { # 硬编码 Channel id
    echoBlue "使用硬编码ID" 1>&2
    case "${isp}" in
        "校园网")
        echo '1'
        return 0;;
        "中国移动")
        echo '2'
        return 0;;
        "中国电信")
        echo '3'
        return 0;;
        "中国联通")
        echo '4'
        return 0;;
        *)
        return 1;;
    esac
}
function CheckAliDns() { # 测试网络通断 0在线
    ping -c 2 223.5.5.5 > /dev/null 2>/dev/null
    # ping -c 2 223.1.1.1 > /dev/null 2>/dev/null
    return $?
}
function CheckLoginServer() { # 测试登录服务器是否在线 0在线
    curl --connect-timeout 5 -H "User-Agent: ${userAgent}" "http://${loginServer}" > /dev/null 2>/dev/null
    return $?
}
function CheckLoginStatus() { # 检查登录状态 0已经登录 1未登录 2未知
    local outport
    outport=$(GetInfo)
    if [[ "$?" -ne '0' ]]; then
        return 2
    fi
    outport=$(echo "${outport}" | grep '网络出口:' | cut -d ':' -f 2)
    case "${outport}" in
        "0.00") # 出现于固定IP 宿舍
            # return 0;;
            return 1;;
        "初始出口")
            return 1;;
        "校园网" | "中国移动" | "中国电信" | "中国联通")
            return 0;;
        *)
            echoRed '出现未知状态' 1>&2
            return 2;;
    esac
}

function CheckAndLogin() { # 进行网络状态检查，然后登录
    echoBlue "测试网络通断..." 1>&2
    CheckAliDns
    if [[ "$?" -eq "0" ]]; then
        if [[ -e "$retryFile" ]]; then
            rm "$retryFile"
            echoBlue "删除临时文件" 1>&2
        fi
        echoBlue "已经联网，退出" 1>&2
        exit 0
    fi

    echoBlue "网络断开，尝试连接登录服务器..." 1>&2
    CheckLoginServer
    if [[ "$?" -ne "0" ]]; then
        echoBlue "登录服务器无法连接，退出..." 1>&2
        if [[ -e "$retryFile" ]]; then
            rm "$retryFile"
            echoBlue "删除临时文件" 1>&2
        fi
        exit 0
    fi

    CheckLoginStatus
    local loginStatus="$?"

    if [[ "${loginStatus}" -eq "0" ]]; then # 断网 API显示登录
        local retry
        if [[ -e "${retryFile}" ]]; then
            retry=$(cat "${retryFile}")
        else
            retry=0
        fi
        echoRed "断网，API显示登录" 1>&2
        retry=$((retry+1)) # 重试次数加1
        if [[ "$retry" -eq "$retryLimit" ]]; then # 重试过多
            echoBlue "重试过多，尝试退出后登陆" 1>&2
            Logout
            channelId=$(GetChannelId)
            if [[ "$?" -ne "0" || -z "${channelId}" ]]; then # 未得到Channel ID
                channelId=$(GetChannelIdOffline)
            fi
            if [[ -z "${channelId}" ]]; then # 未得到Channel ID
                echoRed "channelId缺失，请检测isp设置..." 1>&2
                exit 1
            fi
            Login
            rm "${retryFile}"
        else
            echo "$retry" > "${retryFile}"
        fi
        exit 1
    else # 未登录或者未知
        if [[ "${loginStatus}" -eq "2" ]]; then # 未知
            echoRed "未知情况，默认断网处理" 1>&2
        fi
        channelId=$(GetChannelId)
        if [[ "$?" -ne "0" || -z "${channelId}" ]]; then # 未得到Channel ID
            channelId=$(GetChannelIdOffline)
        fi
        if [[ -z "${channelId}" ]]; then # 未得到Channel ID
            echoRed "channelId缺失，请检测isp设置..." 1>&2
            exit 1
        fi
        Login
        exit "$?"
    fi
}

function ForceLogin() { # 强行登陆
    echoBlue "强制登陆..." 1>&2
    channelId=$(GetChannelId)
    if [[ "$?" -ne "0" || -z "${channelId}" ]]; then # 未得到Channel ID
        channelId=$(GetChannelIdOffline)
    fi
    if [[ -z "${channelId}" ]]; then # 未得到Channel ID
        echoRed "channelId缺失，请检测isp设置..." 1>&2
        exit 1
    fi
    Login
    exit "$?"
}

if [[ "$#" -gt '1' ]]; then
    echoRed "参数过多" 1>&2
    ShowHelp
    exit 1
fi

if [[ "$#" -eq '0' ]]; then
    CheckAndLogin
    exit 0
fi
case "$1" in
    "help")
        ShowHelp
        exit 0;;
    "login")
        ForceLogin
        exit 0;;
    "logout")
        Logout
        exit 0;;
    "status")
        GetInfo
        exit 0;;
    *)
        echoRed "未知参数"
        ShowHelp
        exit 1;;
esac
