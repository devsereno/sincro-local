# 📂 SincroLocal (`sincro-local`) - Especificação Técnica & Ideia

> **Tagline:** Ferramenta robusta e privada de sincronização P2P, migração local e gestão inteligente de armazenamento, sem dependência de nuvem.

---

## ⚙️ 1. Ambiente de Desenvolvimento & Termux (Padrão Obrigatório)
- **Plataforma de Execução:** Dispositivo móvel via **Termux**.
- **Regra de Diretórios:** Todos os comandos de terminal, manipulação de ficheiros e scripts `.sh` **DEVEM** utilizar obrigatoriamente a variável **`$HOME`** para referenciar a raiz do Termux (ex: `$HOME/sincro-local/...`). Proibido o uso de caminhos absolutos genéricos.
- **Repositório Oficial:** `sincro-local`
- **Fluxo de CI/CD:** O código é desenvolvido no telemóvel, versionado via Git e enviado para o repositório privado do GitHub, sendo compilado automaticamente no **Codemagic**.

---

## 🧠 2. Arquitetura e Modos de Armazenamento Inteligente
O aplicativo atua em dois grandes eixos: **Modo P2P (Rede Local)** e **Modo Migração Local (Interna ➔ Cartão SD)**.

### Modos de Destino de Armazenamento:
1. **🔄 Modo Híbrido (Transbordo Inteligente):** Descarrega o máximo possível no Cartão SD. Caso o SD esgote, redireciona o restante automaticamente para a Memória Interna (respeitando o buffer de segurança).
2. **💾 Apenas Cartão SD Externo:** Direciona 100% dos dados para o cartão SD. Se o espaço esgotar, pausa e permite seleção manual do excedente.
3. **📱 Apenas Memória Interna:** Gere o armazenamento na memória principal, aplicando a regra de folga do sistema.

### Buffers de Segurança do Sistema:
* **Memória Interna:** Aplicação de um *buffer* obrigatório (ex: reserva 5GB livres por defeito) para impedir que o Android fique lento ou sofra *crash* por falta de espaço crítico.
* **Cartão SD Externo:** Fundo de utilização quase total, mantendo apenas um buffer mínimo de segurança (ex: 500MB).

---

## 🚀 3. Funcionalidades Principais

* **Radar P2P & Descoberta Local:** Varredura automática de dispositivos na mesma rede Wi-Fi, com opção de fallback via **QR Code**.
* **Segurança TLS & Handshake:** Conexão encriptada P2P validada através de um sistema visual de **3 botões alfanuméricos**.
* **Termômetro de Desempenho & Bateria:** Medição em tempo real da velocidade (`MB/s`) e cálculo do tempo estimado. Inclui um **alerta preventivo de bateria** se o nível estiver baixo, recomendando a ligação ao carregador.
* **Explorador Visual (*Fullscan*):** Árvore detalhada por categorias (`Fotos`, `Vídeos`, `Documentos`, `Downloads`). Permite visualizar ficheiros individualmente ou selecionar em massa.
* **Deleção Permanente (*Bypass* de Lixeira):** Opção de exclusão direta no sistema de ficheiros para libertar espaço real de imediato, protegida por um diálogo de confirmação rigoroso.
* **Histórico Persistente (`Sqflite`):** Registo completo de todas as transferências e migrações. Permite ao utilizador reabrir o explorador *Fullscan* a qualquer momento (dias ou semanas depois) para limpar os originais no seu próprio ritmo.
* **Menu de Configurações (Engrenagem):** Acesso global para definir o modo de armazenamento padrão, ajustar os limites dos *buffers* de segurança e gerir parâmetros de rede.