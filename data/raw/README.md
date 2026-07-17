# Raw Data Directory (Synthetic Only)

⚠️ **重要安全與隱私合規聲明 / IMPORTANT SECURITY & COMPLIANCE NOTICE**

### 🔒 嚴禁存放真實醫療數據 / NO REAL PHI OR PII ALLOWED
本目錄**僅限**存放用於開發與測試的**合成模擬數據（Synthetic Data）**。
為了嚴格遵守醫療隱私法規（如 HIPAA、GDPR 等），**嚴禁**將任何含有真實患者敏感資訊的數據放入此目錄。

這包括但不限於以下真實的 **PHI（受保護健康資訊）** 與 **PII（個人身份識別資訊）**：
* 患者真實姓名、身分證字號、護照號碼
* 真實的聯絡方式（電話、地址、Email）
* 具體的就診日期、病歷號碼、處方內容、診斷報告
* 任何可識別特定個人身份的健康或財務紀錄

---

### 🛠️ 本機開發規範 / Local Development Rules

1. **數據來源驗證**：在將任何新數據放入此目錄前，請務必確認其來源為 `synthetic`（合成/生成數據），且不含任何真實隱私。
2. **Git 與數據規則**：
   * 本目錄只保留小型、固定且經審查的合成 fixture，供 PR CI 快速測試。
   * 會持續增長的合成數據必須寫入已被 `.gitignore` 排除的 `data/generated/`。
   * **切勿**強制提交（`git add -f`）任何大型生成數據或可能包含真實數據的臨時檔案。
3. **安全審查**：若不慎將疑似真實數據的檔案放入此目錄，請立即將其徹底刪除，切勿執行 `git commit` 或 `git push`。若已不慎推送至遠端倉庫，請立即聯絡管理員進行 Git 歷史紀錄徹底抹除。

---

### 📂 目錄內容說明 / Directory Contents
當前目錄下存放的 `.csv` 均為透過 `generate_data.py` 生成並凍結的小型虛擬測試數據，僅供本地 dbt 管道與 DuckDB 數據建模測試使用。請勿在日常測試中持續擴大或覆寫這些 fixture。
