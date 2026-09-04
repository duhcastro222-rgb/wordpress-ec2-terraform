# ADR 0003 - Dois módulos em vez de raiz única ou muitos módulos

**Data:** 2026-09-04
**Status:** aceito

## Contexto

24 recursos precisam ser organizados. As opções vão de tudo na raiz até um
módulo por domínio (rede, computação, IAM, segredos, security group).

## Decisão

Dois módulos: `modules/network` e `modules/wordpress`. A raiz apenas compõe —
não declara nenhum recurso próprio.

## Razões

1. **A fronteira segue o ritmo de mudança, não o tipo de recurso.** A rede é
   provisionada e praticamente nunca muda. A aplicação muda a cada ajuste de
   bootstrap, de porta ou de hardening. Nesta entrega, `modules/wordpress` foi
   alterado quatro vezes e `modules/network` nenhuma. Essa é a fronteira real.

2. **Interface pequena e explícita.** O módulo `network` expõe três outputs:
   `vpc_id`, `public_subnet_id`, `availability_zone`. Quem lê o `main.tf` da
   raiz entende o acoplamento inteiro em três linhas.

3. **Módulo separado para IAM ou security group seria abstração vazia.** Com um
   único recurso de compute, uma role e um security group, cada módulo extra
   adicionaria um arquivo de variáveis e um de outputs para embalar dois
   recursos. Isso é indireção, não organização.

4. **Sem `provider` dentro de módulo.** Quem define região e credencial é
   sempre a raiz. Módulo que configura provider não pode ser reusado em outra
   região sem edição.

## Consequências

- A raiz fica legível: dois blocos `module` e um `locals` com o prefixo de nome.
- `modules/wordpress` concentra security group, IAM, segredos e instância —
  é o módulo maior, e é onde a manutenção acontece.
- Nenhum módulo é publicável em registry como está: ambos recebem
  `name_prefix` já montado, o que é decisão consciente de escopo interno.

## Alternativa recusada

**Tudo na raiz.** Funcionaria e teria menos arquivos. Recusado porque a
distinção entre "rede, que não muda" e "aplicação, que muda toda hora" ficaria
apenas na cabeça de quem escreveu, em vez de estar na estrutura de diretórios.
