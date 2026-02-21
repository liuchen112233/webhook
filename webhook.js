const express = require('express');
const crypto = require('crypto');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const app = express();
const { urlList } = require('./utils/constant.js');

app.use(express.json({ limit: '1mb' })); // 限制请求体大小，防止攻击

// ========== 核心配置（根据你的实际路径修改） ==========
const CONFIG = {
    SECRET: 'webhook_lanya',
    DEPLOY_SCRIPT: 'auto_deploy.bat',
    LOG_DIR: './logs',
    PORT: 9000,
    EXEC_TIMEOUT: 30 * 60 * 1000
};

function resolveEnv(host) {
    const h = (host || '').toLowerCase();
    let branch;
    let buildScript;
    if (urlList.includes(h)) {
        branch = process.env.DEPLOY_BRANCH_TEST || 'dev';
        buildScript = process.env.DEPLOY_BUILD_SCRIPT_TEST || 'build:dev';
    } else {
        branch = process.env.DEPLOY_BRANCH_PROD || 'prod';
        buildScript = process.env.DEPLOY_BUILD_SCRIPT_PROD || 'build';
    }
    return { branch, buildScript };
}

let LOG_DIR_PATH = path.isAbsolute(CONFIG.LOG_DIR) ? CONFIG.LOG_DIR : path.join(__dirname, CONFIG.LOG_DIR);
try {
    const st = fs.existsSync(LOG_DIR_PATH) ? fs.statSync(LOG_DIR_PATH) : null;
    if (!st) {
        fs.mkdirSync(LOG_DIR_PATH, { recursive: true });
    } else if (st.isFile()) {
        LOG_DIR_PATH = path.join(__dirname, 'logs');
        if (!fs.existsSync(LOG_DIR_PATH)) fs.mkdirSync(LOG_DIR_PATH, { recursive: true });
    }
} catch { }
const LOG_FILE = path.join(LOG_DIR_PATH, `deploy_${new Date().toISOString().slice(0, 10)}.log`);

// ========== 日志函数（异步+按天分割） ==========
function log(message) {
    const time = new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' });
    const logMsg = `[${time}] ${message}\n`;
    console.log(logMsg);
    // 异步写入，不阻塞主线程
    fs.appendFile(LOG_FILE, logMsg, (err) => {
        if (err) console.error('日志写入失败：', err);
    });
}

// ========== 签名验证（安全核心） ==========
// GitHub验签
function verifyGitHubSignature(req) {
    const signature = req.headers['x-hub-signature-256'];
    if (!signature) return false;
    try {
        const hmac = crypto.createHmac('sha256', CONFIG.SECRET);
        const digest = 'sha256=' + hmac.update(JSON.stringify(req.body)).digest('hex');
        return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(digest));
    } catch (err) {
        log(`GitHub验签异常：${err.message}`);
        return false;
    }
}

// Gitee验签
function verifyGiteeToken(req) {
    return req.headers['x-gitee-token'] === CONFIG.SECRET;
}

// ========== 执行部署脚本（带超时控制） ==========
const SCRIPT_BAT = path.join(__dirname, 'auto_deploy.bat');
const SCRIPT_SH = path.join(__dirname, 'auto_deploy.sh');
function runDeployScript(reason, config) {
    return new Promise((resolve, reject) => {
        log(`🚀 开始部署 - 原因：${reason}`);
        const deployConfig = config || {};
        const isWin = process.platform === 'win32';
        const scriptPath = isWin ? SCRIPT_BAT : SCRIPT_SH;
        const cmd = isWin ? `"${scriptPath}"` : `bash "${scriptPath}"`;
        const env = {
            ...process.env,
            DEPLOY_GIT_BRANCH: deployConfig.branch,
            DEPLOY_PM2_APP_NAME: deployConfig.pm2AppName,
            DEPLOY_REMOTE_URL: deployConfig.remoteUrl,
            DEPLOY_LOG_PATH: deployConfig.logPath,
            DEPLOY_BUILD_SCRIPT: deployConfig.buildScript
        };
        if (deployConfig.projectDir) {
            env.DEPLOY_PROJECT_DIR = deployConfig.projectDir;
        }
        const child = exec(cmd, {
            timeout: deployConfig.timeout || CONFIG.EXEC_TIMEOUT,
            env
        });

        // 超时处理
        const timeoutTimer = setTimeout(() => {
            child.kill();
            reject(new Error('部署脚本执行超时'));
        }, CONFIG.EXEC_TIMEOUT);

        // 捕获脚本输出
        child.stdout?.on('data', (data) => log(`脚本输出：${data.toString().trim()}`));
        child.stderr?.on('data', (data) => log(`脚本错误输出：${data.toString().trim()}`));

        child.on('close', (code) => {
            clearTimeout(timeoutTimer);
            if (code === 0) {
                resolve('部署成功');
            } else {
                reject(new Error(`脚本执行失败，退出码：${code}`));
            }
        });

        child.on('error', (err) => {
            clearTimeout(timeoutTimer);
            reject(new Error(`脚本执行异常：${err.message}`));
        });
    });
}

// ========== Webhook核心接口 ==========
app.post('/webhook', async (req, res) => {
    try {
        // 1. 判断来源并验证
        const isGitHub = !!req.headers['x-github-event'];
        const isGitee = !!req.headers['x-gitee-event'];
        if (!isGitHub && !isGitee) {
            log('❌ 未知的Webhook来源');
            return res.status(400).send('Unsupported source');
        }

        if (isGitHub && !verifyGitHubSignature(req)) {
            log('❌ GitHub签名验证失败');
            return res.status(401).send('Unauthorized');
        }
        if (isGitee && !verifyGiteeToken(req)) {
            log('❌ Gitee Token验证失败');
            return res.status(401).send('Unauthorized');
        }

        // 2. 解析事件
        const event = isGitHub ? req.headers['x-github-event'] : req.headers['x-gitee-event'];
        const payload = req.body;
        log(`📩 收到 ${isGitHub ? 'GitHub' : 'Gitee'} 事件：${event}`);

        // 3. 判断是否触发部署
        let shouldDeploy = false;
        let deployReason = '';

        // GitHub：PR合并到指定分支
        const host = req.headers.host || '';
        const envInfo = resolveEnv(host);
        console.log(host, 'host')
        console.log(envInfo, 'webhook')
        if (event === 'pull_request' && payload.action === 'closed' && payload.pull_request?.merged) {
            const targetBranch = payload.pull_request.base.ref;
            if (targetBranch === envInfo.branch) {
                shouldDeploy = true;
                deployReason = `GitHub PR #${payload.number} 合并到 ${envInfo.branch}`;
            }
        }
        // Gitee：MR合并到指定分支
        else if (event === 'Merge Request Hook' && payload.action === 'merge') {
            const targetBranch = payload.target_branch;
            if (targetBranch === envInfo.branch) {
                shouldDeploy = true;
                deployReason = `Gitee MR #${payload.iid} 合并到 ${envInfo.branch}`;
            }
        }

        if (!shouldDeploy) {
            log(`⏭️  跳过部署（事件不匹配：${event}）`);
            return res.send('Event ignored');
        }


        const deployConfig = {
            branch: envInfo.branch,
            pm2AppName: 'server',
            remoteUrl: process.env.DEPLOY_REMOTE_URL || 'git@github.com:liuchen112233/yayaspeakingserver.git',
            logPath: process.env.DEPLOY_LOG_PATH || path.join(__dirname, 'deploy.log'),
            timeout: CONFIG.EXEC_TIMEOUT,
            projectDir: "server",
            buildScript: envInfo.buildScript
        };

        // 4. 执行部署（异步，避免请求超时）
        runDeployScript(deployReason, deployConfig)
            .then((msg) => {
                log(`✅ ${msg}`);
            })
            .catch((err) => {
                log(`❌ 部署失败：${err.message}`);
            });

        res.send('Deploy triggered (async)');

    } catch (err) {
        log(`❌ Webhook接口异常：${err.message}`);
        res.status(500).send('Internal server error');
    }
});

app.post('/webhook_client', async (req, res) => {
    try {
        const isGitHub = !!req.headers['x-github-event'];
        const isGitee = !!req.headers['x-gitee-event'];
        if (!isGitHub && !isGitee) {
            log('❌ 未知的Webhook来源');
            return res.status(400).send('Unsupported source');
        }

        if (isGitHub && !verifyGitHubSignature(req)) {
            log('❌ GitHub签名验证失败');
            return res.status(401).send('Unauthorized');
        }
        if (isGitee && !verifyGiteeToken(req)) {
            log('❌ Gitee Token验证失败');
            return res.status(401).send('Unauthorized');
        }

        const event = isGitHub ? req.headers['x-github-event'] : req.headers['x-gitee-event'];
        const payload = req.body;
        log(`📩 [frontend] 收到 ${isGitHub ? 'GitHub' : 'Gitee'} 事件：${event}`);

        let shouldDeploy = false;
        let deployReason = '';
        const host = req.headers.host || '';
        const envInfo = resolveEnv(host);
        console.log(host, 'host')
        console.log(envInfo, 'webhook_client')
        if (event === 'pull_request' && payload.action === 'closed' && payload.pull_request?.merged) {
            const targetBranch = payload.pull_request.base.ref;
            if (targetBranch === envInfo.branch) {
                shouldDeploy = true;
                deployReason = `[frontend] GitHub PR #${payload.number} 合并到 ${envInfo.branch}`;
            }
        } else if (event === 'Merge Request Hook' && payload.action === 'merge') {
            const targetBranch = payload.target_branch;
            if (targetBranch === envInfo.branch) {
                shouldDeploy = true;
                deployReason = `[frontend] Gitee MR #${payload.iid} 合并到 ${envInfo.branch}`;
            }
        }

        if (!shouldDeploy) {
            log(`⏭️  [frontend] 跳过部署（事件不匹配：${event}）`);
            return res.send('Frontend event ignored');
        }

        const deployConfig = {
            branch: envInfo.branch,
            pm2AppName: 'client',
            remoteUrl: process.env.FRONT_DEPLOY_REMOTE_URL || process.env.DEPLOY_REMOTE_URL || 'git@github.com:liuchen112233/lanya.git',
            logPath: process.env.FRONT_DEPLOY_LOG_PATH || path.join(__dirname, 'deploy_frontend.log'),
            timeout: CONFIG.EXEC_TIMEOUT,
            projectDir: "client",
            buildScript: envInfo.buildScript
        };

        runDeployScript(deployReason, deployConfig)
            .then((msg) => {
                log(`✅ [frontend] ${msg}`);
            })
            .catch((err) => {
                log(`❌ [frontend] 部署失败：${err.message}`);
            });

        res.send('Frontend deploy triggered (async)');
    } catch (err) {
        log(`❌ [frontend] Webhook接口异常：${err.message}`);
        res.status(500).send('Internal server error');
    }
});

// ========== 健康检查接口 ==========
app.get('/health', (req, res) => {
    res.json({
        status: 'running',
        time: new Date().toLocaleString('zh-CN'),
        port: CONFIG.PORT
    });
});

// ========== 启动服务 ==========
app.listen(CONFIG.PORT, '0.0.0.0', () => {
    log(`🎯 Webhook CI/CD服务已启动，监听端口：${CONFIG.PORT}`);
    log(`📜 日志文件：${LOG_FILE}`);
});

// ========== 全局错误捕获 ==========
process.on('uncaughtException', (err) => {
    log(`❌ 未捕获异常：${err.message}`);
});
process.on('unhandledRejection', (err) => {
    log(`❌ 未处理的Promise拒绝：${err.message}`);
});
